# Dictionary formats

Every format below ends up as a `Dictionary` (term → frequency) that you
pass to `SymSpellEx.trainDictionary(dict, language)`.

## 1. Plain word list (one word per line)

The simplest format — and a valid Hunspell dictionary as-is:

```text
hola
mundo
palabra
```

```dart
final dict = Dictionary.fromLines(lines);
// => {'hola': 1, 'mundo': 1, 'palabra': 1}
```

Frequency defaults to 1. Fine for validity checks; weak for suggestion
ranking (ties between equidistant candidates are resolved arbitrarily).

## 2. Frequency lists (`word frequency`)

Wolf Garbe / Norvig style, whitespace or tab separated:

```text
the 2313585
of 1315197
and 1296765
```

```dart
final dict = Dictionary.fromLines(lines);
// => {'the': 2313585, 'of': 1315197, ...}
```

This is the recommended format for suggestion quality: the frequencies
drive ranking between equidistant candidates.

## 3. symspell-ex CSV (`term,frequency`)

```text
albert,5
argument,2
```

```dart
final dict = Dictionary.fromLines(lines);
// Also directly trainable: speller.train(lines, language);
```

## 4. Hunspell `.dic` (LibreOffice / Firefox / Chrome / macOS)

Plain text with an optional word-count header, optional `/FLAGS` per word,
escaped slashes and multi-word pairs:

```text
58221
ABS
ADN
trabajar/RQE
and\/or
a lot
```

Use `HunspellDictionary` instead of `Dictionary`:

```dart
final dict = HunspellDictionary.fromString(data);
dict.terms;     // Dictionary: terms with flags stripped
dict.flags;     // Map<String, String>: term -> flags (for .aff expansion)
dict.pairs;     // List<String>: multi-word entries ("a lot")
dict.forbidden; // Set<String>: *word entries from personal dictionaries
```

Parsing rules:

- The first line is skipped if it is a pure integer (word-count header).
- `word/FLAGS` → term `word`, flags recorded in `dict.flags`.
- `and\/or` → term `and/or` (escaped slash inside the word).
- `*word` → added to `dict.forbidden` (lowercased); never trained.
- Entries containing spaces → `dict.pairs` (missing-space corrections).

### Optional `.aff` expansion (full word forms)

Affix-heavy dictionaries store only **stems** with flags; the inflected
forms are generated from the companion `.aff` file. This library supports
that optionally — the `.dic` works alone (stems only), and with the `.aff`
present you get the full vocabulary:

```dart
final dictionary = await AssetDictionaryLoader.loadHunspell(
  'assets/dictionaries/es_ES.dic',
);
final affix = await AssetDictionaryLoader.loadAffix(
  'assets/dictionaries/es_ES.aff',
);

final fullForms = dictionary.expand(affix);   // stems + all generated forms
speller.trainDictionary(fullForms, Languages.spanish);

// Or both at once:
final dict = await AssetDictionaryLoader.loadHunspellWithAffixes(
  'assets/dictionaries/es_ES.dic',
  'assets/dictionaries/es_ES.aff',
);
```

Measured on the real LibreOffice Spanish dictionary: 55,820 stems →
**652,256 forms (11.7x)** in ~1.1 s.

`AffixRules` supports the directives that matter for form generation:
`FLAG` (default / `long` / `num` / `UTF-8`), `PFX` and `SFX` — including
stripping, conditions (`.`, `[abc]`, `[^abc]`, multi-char), cross products
(`Y`/`N`) and `/` continuation classes (e.g. `able/Y` → twofold
suffixation). `SET`, `TRY`, `REP`, `KEY`, `ICONV` and compounding
directives are ignored (they affect ranking/compounds, not the set of
valid forms).

Frequencies of generated forms are 1 (the Hunspell format has no frequency
field), so suggestion ranking within an expanded dictionary is uniform.

## 5. Hunspell personal dictionary

Same plain format, plus two extras:

```text
Kaelen
Foo/Simpson    # adopt the affixation of "Simpson"
*bar           # forbidden word
```

Parsed by `HunspellDictionary.fromLines` as well. The part after `/` in a
personal dictionary is an example word for affix adoption, not flags.

## Exporting dictionaries back to files

Everything that can be parsed can be written back out **as bytes in its own
file format**, so a dictionary can learn new words at runtime and then be
exported with a one-liner:

```dart
// 1) Learn at runtime.
speller.add('kaelen', 7, Languages.english);

// 2) Persist — one line, no string juggling.
File('personal.txt').writeAsBytesSync(speller.exportBytes());

// 3) Reload — the matching one-liner.
final dict = Dictionary.fromBytes(await File('personal.txt').readAsBytes());
speller.trainDictionary(dict, Languages.english);
```

| API | Exports |
|---|---|
| `Dictionary.toBytes()` / `Dictionary.fromBytes()` | `term,frequency` lines, UTF-8 (frequencies preserved) |
| `SymSpellEx.exportBytes([lang])` | the trained state of a language, including runtime-added words |
| `HunspellDictionary.toBytes({includeCountHeader})` / `fromBytes()` | Hunspell `.dic` format: `word`, `word/FLAGS`, pairs, `*forbidden` |

Text-level equivalents are also available: `toLines()`/`toText()` and
`SymSpellEx.exportLines()`, when you prefer working with strings.

Notes:

- `exportBytes`/`exportDictionary` are language-isolated (terms are
  exported from the requested language's namespace only).
- Delete keys are never exported — only real terms.
- The Hunspell format has no frequency field, so `HunspellDictionary`
  export drops frequencies; use `Dictionary.toBytes()` when frequencies
  must survive the round-trip.

## Streaming I/O (chunked reading & writing)

For very large dictionaries (1M+ words), read and write **incrementally** —
never hold the raw file content or a `Dictionary` in memory:

```dart
// READ in chunks: File.openRead() emits byte chunks; multi-byte characters
// and lines split across chunk boundaries are handled correctly.
final dict = await Dictionary.fromByteStream(File('big.txt').openRead());
final hunspell =
    await HunspellDictionary.fromByteStream(File('es.dic').openRead());

// TRAIN straight from the stream — parse a line, train it, discard it.
// No Dictionary, no raw text: memory stays flat regardless of file size.
final speller = SymSpellEx(MemoryStore())..initialize();
await speller.trainByteStream(File('big.txt').openRead(), Languages.english);

// WRITE incrementally and pipe to a file sink (lines batched ~512/chunk).
await speller.exportStream(Languages.english)
    .pipe(File('trained.txt').openWrite());
await hunspell.toByteStream(includeCountHeader: true)
    .pipe(File('saved.dic').openWrite());
```

| API | Direction | Notes |
|---|---|---|
| `Dictionary.fromByteStream` / `fromLineStream` | read | chunk-boundary-safe (UTF-8 + line splitting) |
| `HunspellDictionary.fromByteStream` / `fromLineStream` | read | same, including `.dic` headers/flags |
| `SymSpellEx.trainByteStream` / `trainLineStream` | read | trains line-by-line, constant memory |
| `Dictionary.toByteStream` / `HunspellDictionary.toByteStream` | write | batched chunks |
| `SymSpellEx.exportStream` | write | streams the store directly; insertion order (unsorted) |

Line streams (`*LineStream`) accept `Stream<String>` — build them yourself or
via `utf8.decoder` + `LineSplitter`; the `*ByteStream` variants do that for
you. Measured: streaming 60k lines trains in ~5 s and exports in ~100 ms.

## Loading from Flutter assets

Register the file in `pubspec.yaml` and use the loaders:

```yaml
flutter:
  assets:
    - assets/dictionaries/es_ES.dic
    - assets/dictionaries/en-80k.txt
```

```dart
final hunspell = await AssetDictionaryLoader.loadHunspell(
  'assets/dictionaries/es_ES.dic',
);
final plain = await AssetDictionaryLoader.load(
  'assets/dictionaries/en-80k.txt',
);
```

## Parsing behavior common to all formats

- Lines are trimmed; empty lines and `#` comments are ignored.
- Records whose frequency is not an integer are skipped.
- Terms are stored as-is; `SymSpellEx.add` lowercases and trims when
  training (so dictionaries are effectively case-insensitive).
- Duplicate terms: the last frequency wins.
