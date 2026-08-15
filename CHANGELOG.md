# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-08-15

Initial release: Dart/Flutter port of
[symspell-ex](https://github.com/m-elbably/symspell-ex) (symmetric delete
spelling correction) with a full dictionary ecosystem.

### Added

**Spell-check engine**

- `SymSpellEx`: symmetric delete index with `lookup`/`search` (fuzzy
  suggestions), `correct` (full sentence correction with punctuation,
  spacing and capitalization preservation), `add`/`train`/`trainDictionary`
  (bulk training), `hasTerm` (O(1) exact membership) and `clear`.
- Synchronous API (the original is async only because of its Redis store);
  per-keystroke hot path is allocation-light.
- Multi-language dictionaries with isolated namespaces and runtime
  language switching.
- `MemoryStore` behind a small `DataStore` abstraction.
- `DamerauLevenshteinDistance` (transposition-aware, cached arrays).
- `CoreTokenizer`: url / number / word / punctuation classification for
  latin and arabic alphabets, with spacing metadata (`token.distance`).
- `Trie`: compact packed child/sibling vocabulary with prefix queries
  (`withPrefix`) for validity checks and autocomplete.
- Constants: ~190 `Languages` codes, `TokenTags`, `Alphabets`.

**Dictionary formats & I/O**

- `Dictionary`: plain word lists, `word frequency` lists and
  `term,frequency` CSV — parse (`fromLines`/`fromCsv`/`fromBytes`) and
  export (`toLines`/`toBytes`/`toByteStream`) with lossless round-trips.
- `HunspellDictionary`: `.dic` and personal dictionary parsing (count
  header, `/FLAGS`, escaped slashes, multi-word pairs, `*forbidden`
  entries, UTF-8 BOM) plus export back to Hunspell format.
- `AffixRules`: optional `.aff` support — `FLAG` (default/`long`/`num`/
  `UTF-8`), `PFX`/`SFX` with stripping, conditions (`.`, `[abc]`,
  `[^abc]`, multi-char), cross products and continuation classes.
  `HunspellDictionary.expand(AffixRules)` generates full word forms
  (measured: `es_ES` 55,820 stems → 652,256 forms, 11.7x).
- `AssetDictionaryLoader`: `load`, `loadHunspell`, `loadAffix`,
  `loadHunspellWithAffixes` for Flutter assets.
- Streaming I/O: `fromByteStream`/`fromLineStream`, `trainByteStream`/
  `trainLineStream`, `exportStream`/`toByteStream` — chunk-boundary-safe
  reading and batched writing for very large dictionaries (1M+ words).

**State management**

- `SymSpellEx.exportDictionary`/`exportLines`/`exportBytes`/`exportStream`:
  export trained terms (including runtime-learned words) back to files;
  language-isolated and delete-key-free.
