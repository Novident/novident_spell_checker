# Training your dictionaries and saving them

This guide covers how to build a `SymSpellEx` dictionary from a source file,
how long each step takes on real data, and how to manage the trained state so
you don't rebuild it over and over.

## The training pipeline

```
source file ──parse──▶ Dictionary ──train──▶ SymSpellEx (delete index)
```

For very large dictionaries (1M+ words), skip the intermediate materialization
entirely with stream training — parse a line, train it, discard it:

```dart
final speller = SymSpellEx(MemoryStore())..initialize();
await speller.trainByteStream(File('count_1w.txt').openRead(), Languages.english);
// ...and export the same way later:
await speller.exportStream(Languages.english).pipe(File('trained.txt').openWrite());
```

See [dictionary-formats.md](dictionary-formats.md) for the full streaming API.

Measured on a real LibreOffice dictionary (`es_ES.dic`, 58,221 lines,
55,820 terms) from the stress suite:

| Step | Time | Notes |
|---|---|---|
| Parse (`HunspellDictionary` / `Dictionary`) | 253 ms | ~4,400 lines/ms |
| Train (`trainDictionary`, maxDistance 2) | 3,741 ms | 2,068,565 entries (~37x amplification) |
| Lookup throughput | 26,316 lookups/sec | 5,000 typo lookups in 190 ms |

```dart
final speller = SymSpellEx(MemoryStore())..initialize();

// 1) Parse the source file (plain list, frequencies or Hunspell .dic).
final dict = HunspellDictionary.fromString(
  await rootBundle.loadString('assets/dictionaries/es_ES.dic'),
);

// 2) Train once.
speller.trainDictionary(dict.terms, Languages.spanish);

// 3) Keep the instance alive (see "Avoiding rebuilds" below).
```

`train(List<String>)` accepts raw `term,frequency` lines and `add()` handles
single terms — use whichever matches your source data.

## Avoiding rebuilds: keep the trained state alive

Training a full dictionary costs seconds (see the table). Re-training on
every keystroke, widget rebuild, or document switch is the thing to avoid.
The library is designed so the trained state lives in one place:

### 1. One instance per language, owned by a service (recommended)

```dart
/// Application-wide spell-check state. Create once at startup.
class SpellCheckService {
  final Map<String, SymSpellEx> _spellers = {};

  SymSpellEx forLanguage(String language) {
    return _spellers.putIfAbsent(language, () {
      final speller = SymSpellEx(MemoryStore())..initialize();
      _trainLanguage(speller, language); // parse asset + trainDictionary
      return speller;
    });
  }

  SymSpellEx get english => forLanguage(Languages.english);
  SymSpellEx get spanish => forLanguage(Languages.spanish);
}
```

Use it through your DI/state-management layer (Provider, Riverpod,
GetIt, InheritedWidget — anything that gives you one shared instance).
The widget layer only reads from it; it never creates spellers.

### 2. Split validity and suggestions (biggest startup win)

The delete index (suggestions) is the heavy part: ~37x memory and seconds of
training. Exact membership (what underlines misspelled words) is cheap.

```dart
class SpellCheckService {
  // Fast, small: built eagerly for every language (63 ms / 20k words).
  final Map<String, Trie> _vocabulary = {};

  // Heavy: built lazily, only when the user asks for suggestions.
  final Map<String, SymSpellEx> _suggesters = {};

  Trie vocabulary(String language) => _vocabulary.putIfAbsent(language, () {
    return Trie.fromDictionary(_parseDictionary(language).terms);
  });

  SymSpellEx suggestions(String language) =>
      _suggesters.putIfAbsent(language, () {
        final speller = SymSpellEx(MemoryStore())..initialize();
        speller.trainDictionary(_parseDictionary(language).terms, language);
        return speller;
      });
}
```

Your editor's hot path (marking words as misspelled while typing) uses
`vocabulary().contains(word)`; the heavy index is only built the first time
the user right-clicks a word.

### 3. Re-training at startup is usually fine

If you can't keep state across app restarts, re-training at startup is
acceptable: ~4 s for a 56k-word dictionary, ~250 ms for a 20k one. Show a
loading indicator and train once. This is what most apps do.

### 4. Persisting the trained state

The library ships with an in-memory `DataStore` and does **not** serialize
the trained index itself — but it exports the trained dictionary, which
covers the common case ("the dictionary learned a word, save it back"):

```dart
// Persist learned state as a plain dictionary file — one line.
File('my_dictionary.txt').writeAsBytesSync(speller.exportBytes(Languages.english));

// Next session: re-train from that file (~4 s for a 56k-word dictionary).
final dict = Dictionary.fromBytes(await File('my_dictionary.txt').readAsBytes());
speller.trainDictionary(dict, Languages.english);
```

If your startup budget is tighter than that, you have two options:

- **Persist the source dictionary** (what you parsed — a few hundred KB of
  text), and re-train at startup. `Dictionary.toLines()` re-serializes
  parsed dictionaries; `HunspellDictionary.toText()` re-serializes
  Hunspell files including flags and forbidden words.
- **Implement a file-backed `DataStore`** that writes `setEntry` calls to
  disk and rebuilds the hash maps on `initialize()`. The interface is
  intentionally small:

```dart
class PersistentStore implements DataStore {
  // Store terms (index -> word) and entries (key -> [freq, indexes])
  // in a file of your choice (JSON lines, SQLite, ...). On initialize(),
  // load them back into memory maps. Then training can be skipped.
}
```

Rule of thumb: start with re-training at startup (option 3); only build a
persistent store if you measure startup time is hurting.

## Updating a trained dictionary at runtime

- **Add words** (user personal dictionary): `speller.add(word, 1, language)`
  — O(word length²) for delete-key generation, no rebuild needed.
- **Forbid words** (user says "this is wrong"): keep a per-user
  `Set<String> forbidden` and check it before accepting a word as valid.
  `HunspellDictionary.fromLines` already parses `*word` entries into
  `forbidden`.

```dart
bool isValid(String word, String language) {
  final w = word.toLowerCase();
  if (userForbidden[language]?.contains(w) ?? false) return false;
  return vocabulary(language).contains(w);
}
```

- **Remove words**: the delete index has no cheap removal. For personal
  dictionaries prefer the forbidden-set approach; for a bulk dictionary
  change, rebuild that language's speller (and swap the service entry).
