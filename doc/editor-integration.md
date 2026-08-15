# Using the library in your editor

A practical guide for a WYSIWYG / rich-text editor: how to hold the
spell-check state globally (so dictionaries are never rebuilt), how to
tokenize a paragraph, and how to render misspelled words as styled
`TextSpan`s.

## 1. Global state: one service, built once

Training a full dictionary costs seconds (see
[training-and-persistence.md](training-and-persistence.md)). Never create
`SymSpellEx` (or a `Trie`) inside a widget or on a keystroke — own it in a
single application-level service.

```dart
/// Application-wide spell-check state (Provider / Riverpod / GetIt / plain
/// singleton — whatever your DI layer uses). Created once at startup.
class SpellCheckService {
  SpellCheckService._();
  static final SpellCheckService instance = SpellCheckService._();

  // Cheap exact-membership index per language, built eagerly.
  final Map<String, Trie> _vocabulary = {};
  // Heavy suggestion index per language, built lazily.
  final Map<String, SymSpellEx> _suggesters = {};
  // User's per-language forbidden words (personal dictionary removals).
  final Map<String, Set<String>> _forbidden = {};

  /// Builds the fast vocabulary for [language] (used on every keystroke).
  Trie vocabulary(String language) {
    return _vocabulary.putIfAbsent(language, () {
      final dict = _parseDictionaryAsset(language);
      return Trie.fromDictionary(dict);
    });
  }

  /// Builds the heavy suggestion index only when first needed.
  SymSpellEx suggestions(String language) {
    return _suggesters.putIfAbsent(language, () {
      final speller = SymSpellEx(MemoryStore())..initialize();
      speller.trainDictionary(_parseDictionaryAsset(language).terms, language);
      return speller;
    });
  }

  /// Personal dictionary: words the user added or banned at runtime.
  void addWord(String word, String language) =>
      suggestions(language).add(word, 1, language);

  void forbidWord(String word, String language) =>
      _forbidden.putIfAbsent(language, () => <String>{}).add(
            word.toLowerCase(),
          );

  /// The single word-validity entry point used by the editor hot path.
  bool isValid(String word, String language) {
    final w = word.toLowerCase();
    if (_forbidden[language]?.contains(w) ?? false) return false;
    return vocabulary(language).contains(w);
  }

  Dictionary _parseDictionaryAsset(String language) {
    // AssetDictionaryLoader.loadHunspell / load for the language's .dic.
    // Cache the parsed Dictionary too if you want startup reuse.
    throw UnimplementedError('wire your asset loading here');
  }
}
```

Startup strategy (measured on a real 56k-word dictionary):

- `Trie.fromDictionary` for validity: tens of ms — do it eagerly.
- `trainDictionary` for suggestions: ~3.7 s — do it lazily (first
  right-click) or behind a loading indicator at startup.
- Re-training once per app session is fine; see
  [training-and-persistence.md](training-and-persistence.md) for
  persistence options if you need instant cold starts.

## 2. Tokenizing a full paragraph

`CoreTokenizer.tokenize` returns typed tokens with two fields that make the
round-trip to the original text **exact**:

- `offset` — the token's start position in the original input, so
  misspelled-word ranges map back to the document without drift.
- `spacing` — the exact whitespace that followed the token (spaces, tabs,
  newlines — empty if none). `token.value + token.spacing` over all tokens
  reproduces the input byte-for-byte.

```dart
final tokens = CoreTokenizer().tokenize('In 1905, Einstein wrote.');

for (final token in tokens) {
  print('${token.value} | tag=${token.tag} | offset=${token.offset} | '
      'spacing="${token.spacing}"');
}
// In       | tag=word | offset=0  | spacing=" "
// 1905     | tag=number | offset=3 | spacing=""
// ,        | tag=none | offset=7 | spacing=" "
// Einstein | tag=word | offset=9  | spacing=" "
// ...
```

Rules to remember when consuming tokens:

- Only `tag == TokenTags.word` tokens are spell-checkable.
- Skip words shorter than 2 characters (matches the engine's behavior).
- Untagged tokens (like `,`) are literal text — never looked up.
- Rebuild spacing with `token.spacing` — never from `token.distance`
  (that legacy 0/1 flag only detects a single ASCII space).

## 3. Marking misspelled words with `TextSpan`s

Build the paragraph as a list of spans, applying a distinct style to words
that fail `isValid`:

```dart
List<TextSpan> buildSpellCheckedSpans({
  required String text,
  required String language,
  required TextStyle normal,
  required TextStyle misspelled,
}) {
  final service = SpellCheckService.instance;
  final spans = <TextSpan>[];

  for (final token in CoreTokenizer().tokenize(text)) {
    var style = normal;

    if (token.tag == TokenTags.word && token.value.length >= 2) {
      if (!service.isValid(token.value, language)) {
        style = misspelled;
      }
    }

    // Re-attach the exact original spacing.
    spans.add(TextSpan(text: token.value + token.spacing, style: style));
  }

  return spans;
}

// Usage inside a widget:
Text.rich(
  TextSpan(children: buildSpellCheckedSpans(
    text: paragraph,
    language: Languages.english,
    normal: const TextStyle(color: Colors.black),
    misspelled: const TextStyle(
      color: Colors.red,
      decoration: TextDecoration.underline,
      decorationColor: Colors.red,
      decorationStyle: TextDecorationStyle.wavy,
    ),
  )),
);
```

Typical editor integration:

- **Debounce**: re-run the span builder for the edited paragraph ~300 ms
  after the last keystroke (or use the document model's change events).
- **Differential checks**: if your document model gives you per-word
  changes, only re-check the changed words instead of the whole paragraph.
- **Cursor/IME care**: spans are static text; a WYSIWYG editor will merge
  this with its own editing controller — keep the mapping token → text
  range so you can jump to the next misspelled word.

## 4. Suggestions on demand (context menu)

The heavy index is only touched when the user asks:

```dart
void showSuggestions(BuildContext context, String word, String language) {
  final suggestions = SpellCheckService.instance
      .suggestions(language)
      .lookup(word, language: language, maxSuggestions: 7);

  // Show a context menu; on tap, replace the word in the document.
  for (final s in suggestions) {
    print('${s.suggestion} (distance ${s.distance})');
  }
}
```

## 5. Runtime personal dictionary (fiction writers' names, invented terms)

- **Add** (`addWord` above): trains the term into the suggestion index
  immediately; O(term length²) — instant for normal words.
- **Forbid** (`forbidWord` above): checked in `isValid` before the
  vocabulary, so the word is flagged without touching the indexes.
- On bulk dictionary replacement: swap the service entry for that language
  (rebuild once, drop the old instance).

## 6. Checklist for your editor

- [ ] One `SpellCheckService` per app (DI), never per widget/keystroke.
- [ ] Validity index (`Trie`) per language built eagerly at startup.
- [ ] Suggestion index (`SymSpellEx`) per language built lazily.
- [ ] Per-language asset dictionary loaded once (`AssetDictionaryLoader`).
- [ ] Forbidden set per user/language checked before vocabulary.
- [ ] Spans rebuilt with debounce; spacing reconstructed via
      `token.spacing` (exact), offsets taken from `token.offset`.
- [ ] Context menu reads from the lazy `suggestions(language)`.
