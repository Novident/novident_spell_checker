# What the tests cover

The test suite is organized in five layers, from unit behavior to
real-world validation and performance.

## 1. `test/novident_spell_checker_test.dart` — engine unit tests

Ported from the original symspell-ex suite plus additions:

- Instance lifecycle (`initialize`, readiness errors).
- Constructor configuration (`maxDistance`, `maxSuggestions`, custom
  edit distance and tokenizer).
- Tokenizer behavior on sentences, numbers, words, punctuation.
- Basic corrections (exact matches, capitalization preservation).
- `lookup` / fuzzy search: distances, frequency ranking at equal distance,
  `maxSuggestions`, long-term early exit.
- `add` / `train`: frequencies, empty entries, one-character terms,
  delete-key deduplication on re-add.
- Arabic corrections and language isolation.
- `clear()` and Damerau-Levenshtein reference distances.

## 2. `test/dictionary_test.dart`, `test/hunspell_dictionary_test.dart`,
   `test/trie_test.dart` — dictionary layer

- `Dictionary`: comma format, whitespace format, plain word lists,
  comments/malformed records, `fromCsv`, `toLines` round-trip.
- `HunspellDictionary`: count header, `/FLAGS`, escaped slashes,
  personal dictionaries (`*forbidden`, affix adoption), multi-word
  pairs, UTF-8 BOM.
- `AssetDictionaryLoader` / `loadHunspell` with an in-memory bundle.
- `Trie`: insert/contains, prefix sharing, dedup, `withPrefix` (order and
  limit), case normalization, unicode.
- `SymSpellEx.hasTerm`: terms vs delete keys, language awareness,
  dictionary-trained words.

## 3. `test/real_world_test.dart` — standard real-world data sets

Assets in `test/assets/`:

| Asset | Origin |
|---|---|
| `norvig/spell-errors.txt` | Peter Norvig — 7,841 lines of real misspellings (Wikipedia + Roger Mitton) → 38,865 cases |
| `dictionaries/en_count_big.txt` | Norvig — 29,136 real English words with counts |
| `dictionaries/sgb_words.txt` | Knuth's Stanford GraphBase — 5,757 five-letter words, plain list |
| `dictionaries/es_ES.dic` | LibreOffice — real Spanish Hunspell dictionary (58,221 lines) |
| `dictionaries/es_common.txt`, `es_personal.txt` | Curated Spanish list + personal dictionary |

Guarantees enforced:

- **Norvig standard set** (38,865 cases): every misspelling whose correct
  word is covered and within `maxDistance` is found — `engine misses == 0`.
  Misses are categorized and quantified: contextual (typed word is valid),
  out-of-range (distance > 2), closer-word (engine found a better
  candidate), lost ties (frequency ranking).
- **Self-validation**: all 29,136 dictionary words are recognized exactly
  (distance 0).
- **Typo recall**: 2,000 real words with an injected substitution typo —
  ≥ 98% recall (remaining misses are typos that form another valid word).
- **Spanish**: accented words recognized, realistic typo corrections,
  full-sentence correction.
- **Personal dictionary**: forbidden words parsed and kept out.

## 4. `test/stress/stress_test.dart` — performance & scale

Skipped by default; run with `--dart-define=STRESS=true`. Deterministic
(fixed seeds), with logged timings and generous budgets to catch
catastrophic regressions:

- 20k-term dictionary training and lookups.
- 200-char words (~20,100 delete keys), 40-char words at `maxDistance` 3.
- 1k/10k-word sentence correction (90 KB, 500 typos) with exact output.
- Lookup throughput over a 5k dictionary (~24k lookups/sec).
- Vocabulary structures comparison: SymSpell delete index vs `Set` vs
  `Trie` (build, probe throughput, memory proxy).
- **Hunspell pipeline** on the real `es_ES.dic`: parse, train
  (2M entries, 37x amplification), 5k typo lookups with recall, asset
  loader timing.
- Memory hygiene after `clear()`.

```sh
flutter test --dart-define=STRESS=true test/stress/stress_test.dart \
  --reporter expanded
```

## 5. Running everything

```sh
flutter analyze          # static analysis
flutter test             # layers 1-3 (stress tests appear as skipped)
```

## What is NOT covered (honest gaps)

- `.aff` affix expansion (flags are parsed, not applied).
- Context-aware corrections (a valid word is never replaced).
- Diacritic-insensitive matching (`tu` vs `tú`).
- Store serialization across app restarts.
- Concurrency/isolate training.
