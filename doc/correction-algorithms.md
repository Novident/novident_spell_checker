# Correction algorithms

What runs under the hood, in the order the text passes through the engine.

## Pipeline

```
text ──tokenize──▶ tokens ──(word?)──▶ hasTerm / lookup ──▶ suggestions
```

## 1. Tokenizer (`CoreTokenizer`)

Splits input into typed `Token`s using a cascade of regular expressions
(latin + arabic): url → number → word → punctuation → space. Untagged
segments recurse until classified.

```dart
final tokens = CoreTokenizer().tokenize('In 1905, Einstein wrote.');
// [Token('In', tag: word, offset: 0, spacing: ' '), Token('1905', tag: number), ...]
```

Key properties:

- `tag` — `url`, `number`, `word`, `punctuation`, `space`, `none`.
- `offset` — the token's start position in the original input; exact
  misspelled-range mapping for editors.
- `spacing` — the exact whitespace that followed the token (multi-spaces,
  tabs, newlines included). Rebuilding `value + spacing` reproduces the
  input losslessly; the legacy `distance` field is only a 0/1
  single-space flag.
- Non-word tokens (`numbers`, urls, punctuation) are never looked up.

Known quirk (faithful to the original): `,` is not in the punctuation
class, so it keeps the `none` tag — harmless, it is still not looked up.

## 2. Exact membership (`hasTerm` / `Trie`)

"Is this word valid?" — O(1) hash lookup for terms with frequency > 0.
Delete keys (frequency 0) correctly answer `false`.

- `SymSpellEx.hasTerm(term, language)` — case-insensitive, O(1).
- `Trie` — compact alternative with prefix queries (autocomplete),
  built from a plain word list.

## 3. Fuzzy lookup: symmetric delete (SymSpell)

The core algorithm, by Wolf Garbe. For every dictionary term, all variants
with up to `maxDistance` characters **deleted** are precomputed and stored
as "delete keys" pointing back to the term. A misspelled word is corrected
by deleting characters from it and looking the results up:

```
dictionary:  albert → deletes: lbert, abert, albrt, albet, alber, ...
typo:         albet  → found directly as a delete key → albert (distance 1)
```

Properties:

- **Constant-time lookups** with respect to dictionary size (only depends
  on word length and `maxDistance`).
- **Language independent** — only deletions are generated, never
  alphabet-dependent edits.
- Covers insertions, deletions, substitutions and transpositions
  (Damerau-Levenshtein ≤ `maxDistance`).
- **Memory cost**: a term of length L with `maxDistance` 2 generates
  ~C(L,1)+C(L,2) delete keys (measured: 37x amplification on a real
  56k-word dictionary).

Lookup returns only suggestions at the **minimal** edit distance found
(behavior inherited from symspell-ex); ties are ranked by frequency.

## 4. Edit distance: Damerau-Levenshtein

`DamerauLevenshteinDistance` — supports transpositions ("hlelo" → "hello"
= 1). The lookup pre-filtering uses a common prefix/suffix optimization
(compute the distance only on the differing middle), which makes the BFS
fast in practice.

Swap in a different metric by implementing `EditDistance`.

## 5. Sentence correction (`correct`)

Tokenizes the input, looks up each word token (`maxSuggestions: 1`),
preserves the original spacing through `token.distance`, restores leading
capitalization, and returns a `Correction`:

```dart
final c = speller.correct('albrt did groundbrekin work.', Languages.english);
c.output;      // 'albert did groundbreaking work.'
c.suggestions; // per-token Suggestion list
```

## Structure choice: validity vs suggestions

| Need | Structure | Cost |
|---|---|---|
| Is this word wrong? (underline while typing) | `hasTerm` / `Set` / `Trie` | ~1x memory, O(1) |
| What should it be? (context menu) | delete index via `lookup` | ~37-42x memory |
| Autocomplete / prefixes | `Trie` | ~5x memory |

## Known limitations (by design)

- **No context**: a valid word is never "corrected" even when another word
  was intended ("look" vs "looking"). That's why the standard Norvig test
  set classifies those cases as contextual misses.
- **Diacritics are distinct**: `tu` and `tú` do not cross-match via delete
  keys. Dictionaries should include both variants (real ones do).
- **Ranking needs frequencies**: with a flat word list, ties between
  equidistant candidates are arbitrary.
- **Words of length 1** are exact-match only (no delete keys, no
  suggestions).
- **maxDistance** defaults to 2; human errors beyond that (multi-edit,
  phonetic) are out of range by design.
