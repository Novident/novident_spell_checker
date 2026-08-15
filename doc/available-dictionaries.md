# Available dictionaries

Where to get real dictionaries, what format each one is in, and how to wire
them into this library.

## LibreOffice dictionaries (recommended for editors)

The best-curated per-language dictionaries in existence, used by LibreOffice,
Firefox, Chrome and macOS. Format: Hunspell (`.dic` + `.aff`).

- Repository: <https://cgit.freedesktop.org/libreoffice/dictionaries/>
  (GitHub mirror: <https://github.com/LibreOffice/dictionaries>)
- One folder per language: `es/es_ES.dic`, `en/en_US.dic`, `de/de_DE.dic`, …

```dart
// pubspec.yaml → assets: - assets/dictionaries/es_ES.dic
final dict = await AssetDictionaryLoader.loadHunspell(
  'assets/dictionaries/es_ES.dic',
);
speller.trainDictionary(dict.terms, Languages.spanish);
```

Notes:

- **Affix-heavy languages** (German, Hungarian, …): `.dic` stores stems and
  the `.aff` generates the inflected forms — ship both files and use
  `HunspellDictionary.expand(AffixRules)` / `loadHunspellWithAffixes` to
  get the full vocabulary (see
  [dictionary-formats.md](dictionary-formats.md)).
- **Licenses**: each dictionary folder carries its own license
  (`GPLv3.txt`, `LGPLv3.txt`, `MPL-1.1.txt`, …). Check them for
  proprietary apps — many are GPL/LGPL/MPL.

## Norvig's corpus data (English)

From <https://norvig.com/ngrams/> (MIT):

| File | Content | Use for |
|---|---|---|
| `count_1w.txt` | 333,333 words with counts (1.7 MB) | Best frequency source for suggestion ranking |
| `count_big.txt` | 29,136 words with counts | Smaller alternative (shipped as test asset) |
| `spell-errors.txt` | Real misspellings `right: wrong1, wrong2` | Validation test data (shipped as test asset) |
| `sgb-words.txt` | 5,757 five-letter words (Knuth) | Plain word list (shipped as test asset) |

```dart
// count_1w.txt is tab-separated "word\tcount" — plain Dictionary handles it.
final dict = Dictionary.fromLines(
  File('count_1w.txt').readAsLinesSync(),
);
```

## Wolf Garbe's SymSpell dictionaries

From <https://github.com/wolfgarbe/SymSpell>:

| File | Content |
|---|---|
| `frequency_dictionary_en_82_765.txt` | 82,765 English words with frequencies (`word frequency`) |
| `frequency_bigramdictionary_en_243_342.txt` | word + bigram frequencies (noisy-channel ranking) |

Space-separated `word frequency` — parsed directly by `Dictionary.fromLines`.

## Word-game lists (plain lists, no frequencies)

- SOWPODS (267,750 words), TWL06 (178,690), ENABLE (172,819) — Scrabble
  lists from <https://norvig.com/ngrams/>.
- Good for validity-only checking; useless for suggestion ranking
  (all frequencies are 1 — ties are resolved arbitrarily).

## Building your own

- **Plain list**: any `.txt` with one word per line.
- **With frequencies**: `word frequency` (whitespace or tab separated) or
  `word,frequency`.
- **Personal dictionaries**: Hunspell personal format with `*forbidden`
  entries — see [dictionary-formats.md](dictionary-formats.md).

## Shipped test assets

`test/assets/` includes real data used by the test suite
(see [testing.md](testing.md)): `es_ES.dic` (LibreOffice), `en_count_big.txt`
and `spell-errors.txt` (Norvig), `sgb_words.txt` (Knuth), plus curated
Spanish and personal dictionaries.
