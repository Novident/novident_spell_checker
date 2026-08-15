# Novident Spell Checker 

Spelling correction & fuzzy search for the **Novident** suite, based on the **symmetric
delete spelling correction algorithm**.

Dart port of [symspell-ex](https://github.com/m-elbably/symspell-ex) (MIT) with some extra things for convenience.

## Features

- Symmetric delete index: fast lookup (~6 orders of magnitude faster than
  linear scan) with tunable `maxDistance`.
- Damerau-Levenshtein edit distance (supports transpositions).
- Context-aware tokenizer (url / number / word / punctuation) for latin and
  arabic alphabets.
- Multi-language dictionaries with isolated namespaces.
- In-memory store with a synchronous API — no `Future` overhead on the
  per-keystroke hot path.
- `correction` for full sentences, `lookup`/`search` for fuzzy suggestions,
  `train` for bulk dictionaries.

> **API note:** the original symspell-ex API is `async` only because of its
> Redis store. This port keeps a `DataStore` abstraction, but the default
> `MemoryStore` (and the whole `SymSpellEx` facade) is synchronous.

## In-depth documentation

Deeper guides live in [`docs/`](docs/):

| Guide | Contents |
|---|---|
| [Training & persistence](docs/training-and-persistence.md) | How to train dictionaries, measured timings, and how to keep the trained state alive (avoiding full rebuilds) |
| [Dictionary formats](docs/dictionary-formats.md) | Every accepted format: plain lists, frequency lists, CSV, Hunspell `.dic` and personal dictionaries |
| [Available dictionaries](docs/available-dictionaries.md) | Where to get real dictionaries (LibreOffice, Norvig, Wolf Garbe, word lists) and their licenses |
| [Correction algorithms](docs/correction-algorithms.md) | How the tokenizer, exact membership, symmetric delete and Damerau-Levenshtein work, with known limitations |
| [Editor integration](docs/editor-integration.md) | Global state management, tokenizing paragraphs and marking misspelled `TextSpan`s in a WYSIWYG editor |
| [Testing](docs/testing.md) | What each test suite covers and how to run it |

## Getting started

Add the dependency to `pubspec.yaml`:

```yaml
dependencies:
  novident_spell_checker: <latest> 
```

## Usage

```dart
import 'package:novident_spell_checker/novident_spell_checker.dart';

void main() {
  final symSpell = SymSpellEx(MemoryStore())..initialize();

  // Bulk training: each item is 'term,frequency'.
  symSpell.train(
    const [
      'albert,5',
      'argument,2',
      'academically,8',
      'groundbreaking,4',
    ],
    Languages.english,
  );

  // Add terms one by one.
  symSpell.add('relativity', 3, Languages.english);

  // Fuzzy lookup.
  final suggestions = symSpell.lookup('acaddemicaly');
  print(suggestions.first.suggestion); // academically

  // Full sentence correction.
  final correction = symSpell.correct(
    'albrt did groundbrekin academically work.',
    Languages.english,
  );
  print(correction!.output); // albert did groundbreaking academically work.
  for (final s in correction.suggestions) {
    print('${s.term} -> ${s.suggestion} (distance ${s.distance})');
  }
}
```

### Configuration

```dart
final symSpell = SymSpellEx(
  MemoryStore(),
  editDistance: DamerauLevenshteinDistance(),
  tokenizer: CoreTokenizer(),
  maxDistance: 3,
  maxSuggestions: 10,
)..initialize();
```

### Extending

- Custom stores: implement `DataStore`.
- Custom edit distance: implement `EditDistance`.
- Custom tokenizers: implement `Tokenizer`.

## Dictionary storage & word validity

There are two complementary problems:

1. **Is this word valid?** (exact membership) — `SymSpellEx.hasTerm()` answers
   in O(1) via the hash store. A standalone `Trie` does the same when you
   don't need fuzzy suggestions and want a smaller footprint.
2. **What should this typo be?** (fuzzy correction) — solved by the symmetric
   delete index, which is the memory-heavy part: a term of length L with
   `maxDistance` 2 generates ~C(L,1)+C(L,2) delete keys.

`Dictionary` accepts all common formats, so a user can pass a plain word
list, a Wolf Garbe frequency file or symspell-ex CSV records:

```dart
// Plain .txt word list ("word" per line) — frequency defaults to 1.
final dict = Dictionary.fromLines(File('words.txt').readAsLinesSync());
symSpell.trainDictionary(dict, Languages.english);

// Bundled Flutter asset.
// pubspec.yaml:
//   flutter:
//     assets:
//       - assets/dictionaries/en-80k.txt
final dict = await AssetDictionaryLoader.load('assets/dictionaries/en-80k.txt');
symSpell.trainDictionary(dict, Languages.english);

// Exact membership ("is this word misspelled?").
symSpell.hasTerm('albert'); // true
symSpell.hasTerm('albrt');  // false (it's a delete key, not a term)
```

### Compact vocabulary with `Trie`

A plain word list can also be compiled into a `Trie` for compact exact
lookups and autocomplete — useful when the app only needs to *flag* unknown
words (no suggestions):

```dart
final trie = Trie.fromDictionary(dict);
trie.contains('albert');            // true
trie.withPrefix('alb', limit: 5);   // ['albert', ...]
```

`Trie` uses packed child/sibling arrays (4 ints per node, no per-node
objects or maps) instead of the naive node-per-char design, which in Dart
loses to `Set<String>` on memory due to object overhead.

Measured on 20k synthetic words (see the stress suite):

| Structure | Build | 50k exact probes | Size proxy |
|---|---|---|---|
| SymSpell delete index | 1,515 ms | 158 ms | 837k entries (**41.9x**) |
| `Set<String>` | 11 ms | 16 ms | 20k strings (1x) |
| `Trie` | 29 ms | 61 ms | 97k nodes (4.9x) |

**Rule of thumb:** use `Set`/`hasTerm` for validity-only checks; add `Trie`
when you need prefix queries; pay the ~40x delete-index cost only when you
need fuzzy suggestions (`lookup`/`correct`).

### Hunspell dictionary

The Hunspell `.dic` format (LibreOffice, Firefox, Chrome, macOS
dictionaries) is plain text: one word per line, optionally `word/FLAGS`.
A plain word list is already a valid Hunspell dictionary. Use
`HunspellDictionary` to consume that ecosystem directly:

```dart
// Main dictionary: parses the count header, strips /FLAGS,
// handles escaped slashes and multi-word pairs.
final dict = HunspellDictionary.fromString(
  await rootBundle.loadString('assets/dictionaries/es_ANY.dic'),
);
symSpell.trainDictionary(dict.terms, Languages.spanish);

// Personal dictionary: word lists with *forbidden entries.
final personal = HunspellDictionary.fromString(
  await rootBundle.loadString('assets/dictionaries/es_personal.dic'),
);
symSpell.trainDictionary(personal.terms, Languages.spanish);

// Check a word: forbidden entries are never trained, so check them first.
bool isValid(String word) =>
    !personal.forbidden.contains(word.toLowerCase()) &&
    symSpell.hasTerm(word, Languages.spanish);
```

Or via assets: `AssetDictionaryLoader.loadHunspell('assets/dictionaries/es.dic')`.

Notes:

- Flags are parsed but **not expanded**. For morphologically rich languages
  prefer full-form dictionaries (e.g. `es_ANY.dic` for Spanish) or implement
  `.aff` expansion as a build step.
- LibreOffice dictionary files ship in
  [cgit.freedesktop.org/libreoffice/dictionaries](https://cgit.freedesktop.org/libreoffice/dictionaries/);
  check each dictionary's license (many are GPL/LGPL/MPL).

## Real-world validation

`test/real_world_test.dart` validates the engine against standard public
data sets (`test/assets/`):

| Asset | Content |
|---|---|
| `norvig/spell-errors.txt` | 7,841 lines of real misspellings from Wikipedia + Roger Mitton's corpus (Peter Norvig's standard test set) → 38,865 cases |
| `dictionaries/en_count_big.txt` | 29,136 real English words with counts (from Norvig's `big.txt` corpus) |
| `dictionaries/sgb_words.txt` | 5,757 five-letter words from Knuth's Stanford GraphBase (plain list, no frequencies) |
| `dictionaries/es_common.txt` | Spanish frequency list with accented words |
| `dictionaries/es_personal.txt` | Hunspell-style personal dictionary |

Measured results (deterministic):

```
[REAL] spell-errors: 38865 cases, coverage 89.1%,
       top-1 accuracy 32.4% overall / 69.1% fair / 78.3% ranking
[REAL] misses: 3250 contextual (typed word valid), 13137 out-of-range,
       2160 closer-word, 3483 lost ties, 0 engine misses
[REAL] typo recall: 2000 sampled words, 0.3% misses (typo is another valid word)
```

The suite also guarantees: every dictionary word is recognized exactly
(self-validation), distance-1 typos of real words are recalled, and
`engine misses == 0` on the standard set (every covered case within
`maxDistance` is found). Remaining top-1 misses are ranking ties — they
improve with a larger frequency dictionary (e.g. Norvig's 333k-word
`count_1w`), not with engine changes.

## Stress testing

`test/stress/stress_test.dart` contains deterministic stress tests (fixed RNG
seeds) with large strings: a 20k-term dictionary, 200-char words
(~20,100 delete keys), 10k-word sentences (~90 KB) with 500 injected typos,
and lookup throughput benchmarks.

It also benchmarks the **Hunspell pipeline** against the real
`es_ES.dic` from LibreOffice (58,221 lines / 700 KB, test asset):

```
[STRESS] parse es_ES.dic:  253 ms (55,820 terms, 47,332 flagged)
[STRESS] train es_ES:      3,741 ms (2,068,565 entries, 37.1x amplification)
[STRESS] 5,000 typo lookups: 190 ms (26,316 lookups/sec, recall 97.9%)
[STRESS] loadHunspell:     270 ms (700 KB asset)
```

They are excluded from the default test suite. Run them with:

```sh
flutter test --dart-define=STRESS=true test/stress/stress_test.dart \
  --reporter expanded
```

## Additional information

- Original: [m-elbably/symspell-ex](https://github.com/m-elbably/symspell-ex)
- Algorithm: symmetric delete spelling correction
  (SymSpell by Wolf Garbe).
- License: MIT.
