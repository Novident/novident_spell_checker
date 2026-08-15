import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'core/constants.dart';
import 'core/data_store.dart';
import 'core/edit_distance.dart';
import 'core/nlp/edit_distance/damerau_levenshtein.dart';
import 'core/nlp/tokenizers/core_tokenizer.dart';
import 'core/tokenizer.dart';
import 'core/types.dart';
import 'dictionaries/dictionary.dart';

/// Spelling correction & fuzzy search based on the symmetric delete spelling
/// correction algorithm.
///
/// Dart port of `symspell-ex` (https://github.com/m-elbably/symspell-ex).
///
/// The API is synchronous (the original library is async only because of its
/// Redis store), which makes per-keystroke correction in Flutter UIs
/// allocation-light.
class SymSpellEx {
  static const int defaultMaxDistance = 2;
  static const int defaultMaxSuggestions = 5;

  final DataStore store;
  final EditDistance editDistance;
  final Tokenizer _tokenizer;
  final int maxDistance;
  final int maxSuggestions;

  String _language = Languages.english;
  bool _isInitialized = false;

  SymSpellEx(
    this.store, {
    EditDistance? editDistance,
    Tokenizer? tokenizer,
    this.maxDistance = defaultMaxDistance,
    this.maxSuggestions = defaultMaxSuggestions,
  }) : editDistance = editDistance ?? DamerauLevenshteinDistance(),
       _tokenizer = tokenizer ?? CoreTokenizer();

  void initialize() {
    store.initialize();
    _isInitialized = true;
  }

  bool isInitialized() => _isInitialized;

  String get language => _language;

  void setLanguage(String language) {
    _checkForReadiness();
    _language = language;
    store.setLanguage(language);
  }

  void _checkForReadiness() {
    if (!_isInitialized) {
      throw StateError(
        'SymSpellEx must be initialized, Please call initialize() first',
      );
    }
  }

  /// Generates all delete variants of [word] down to depth [max] (exclusive),
  /// starting from depth [min].
  Set<String> _edits(String word, int min, int max, Set<String> deletes) {
    min++;

    final l = word.length;
    if (l > 1) {
      for (var i = 0; i < l; i++) {
        final deletedItem = word.substring(0, i) + word.substring(i + 1);
        if (deletes.add(deletedItem) && min < max) {
          _edits(deletedItem, min, max, deletes);
        }
      }
    }

    return deletes;
  }

  List<Suggestion> _filterAndRankSuggestions(
    List<Suggestion> suggestions,
    int max,
  ) {
    if (suggestions.isEmpty) {
      return const [];
    }

    final sorted = List<Suggestion>.of(suggestions)
      ..sort((a, b) {
        final byDistance = a.distance.compareTo(b.distance);
        return byDistance != 0
            ? byDistance
            : b.frequency.compareTo(a.frequency);
      });

    return sorted.take(max).toList(growable: false);
  }

  /// Looks up spelling suggestions for [term].
  List<Suggestion> lookup(
    String term, {
    String? language,
    int? maxDistance,
    int? maxSuggestions,
  }) {
    _checkForReadiness();

    final iLanguage = language ?? _language;
    final iMaxDistance = maxDistance ?? this.maxDistance;
    final iMaxSuggestions = maxSuggestions ?? this.maxSuggestions;
    final iTerm = term.toLowerCase().trim();
    final iLength = iTerm.length;
    final maxKeyLength = store.maxEntryLength();

    // Always (re)apply the language: the `_language` instance field only
    // tracks the default, while the store's current language must follow
    // the requested one — otherwise mixed explicit languages would file
    // entries under the wrong namespace.
    store.setLanguage(iLanguage);

    if (iLength - iMaxDistance > maxKeyLength) {
      return const [];
    }

    var termsCache = <String?>[];
    String candidate;
    var candidateHasHigherDistance = false;
    var inputCandidateDistance = 0;

    final candidates = ListQueue<String>()..add(iTerm);
    final candidateSet = <String>{};

    var suggestions = <Suggestion>[];
    final suggestionSet = <String>{};

    while (candidates.isNotEmpty) {
      candidate = candidates.removeFirst();

      inputCandidateDistance = iLength - candidate.length;
      candidateHasHigherDistance =
          suggestions.isNotEmpty &&
          inputCandidateDistance > suggestions[0].distance;
      if (candidateHasHigherDistance) {
        break;
      }

      final entry = store.getEntry(candidate);
      if (entry != null) {
        if (entry[0] > 0 && !suggestionSet.contains(candidate)) {
          final suggestion = Suggestion(
            term,
            candidate,
            inputCandidateDistance,
            entry[0],
          );
          suggestionSet.add(candidate);
          suggestions.add(suggestion);

          if (inputCandidateDistance == 0) {
            break;
          }
        }

        termsCache = store.getTermsAt(entry);
        for (var i = 1; i < entry.length; i++) {
          final sIndex = entry[i];
          final sTerm = (i < termsCache.length && termsCache[i] != null)
              ? termsCache[i]
              : store.getTermAt(sIndex);
          if (sTerm == null) {
            continue;
          }

          if (suggestionSet.contains(sTerm)) {
            continue;
          }
          suggestionSet.add(sTerm);

          // Computing distance between candidate & suggestion.
          var distance = 0;
          if (iTerm != sTerm) {
            if (sTerm.length == candidate.length) {
              distance = iLength - candidate.length;
            } else if (iLength == candidate.length) {
              distance = sTerm.length - candidate.length;
            } else {
              var ii = 0;
              var jj = 0;
              final sLen = sTerm.length;

              while (ii < sLen && ii < iLength && sTerm[ii] == iTerm[ii]) {
                ii++;
              }

              while (jj < sLen - ii &&
                  jj < iLength &&
                  sTerm[sLen - jj - 1] == iTerm[iLength - jj - 1]) {
                jj++;
              }

              if (ii > 0 || jj > 0) {
                distance = editDistance.calculateDistance(
                  sTerm.substring(ii, sLen - jj),
                  iTerm.substring(ii, iLength - jj),
                );
              } else {
                distance = editDistance.calculateDistance(sTerm, iTerm);
              }
            }
          }

          if (suggestions.isNotEmpty) {
            if (distance < suggestions[0].distance) {
              suggestions = [];
            } else if (distance > suggestions[0].distance) {
              continue;
            }
          }

          if (distance <= iMaxDistance) {
            final suggestionEntry = store.getEntry(sTerm);
            if (suggestionEntry != null) {
              suggestions.add(
                Suggestion(term, sTerm, distance, suggestionEntry[0]),
              );
            }
          }
        }
      }

      if (iLength - candidate.length < iMaxDistance) {
        if (candidateHasHigherDistance) {
          continue;
        }

        for (var i = 0; i < candidate.length; i++) {
          final deletedItem =
              candidate.substring(0, i) + candidate.substring(i + 1);
          if (!candidateSet.contains(deletedItem)) {
            candidates.add(deletedItem);
            candidateSet.add(deletedItem);
          }
        }
      }
    }

    return _filterAndRankSuggestions(suggestions, iMaxSuggestions);
  }

  /// Adds a single [term] to the dictionary.
  void add(
    String term, [
    int frequency = 1,
    String? language,
    int? maxDistance,
  ]) {
    _checkForReadiness();
    if (term.isEmpty) {
      return;
    }

    final iLanguage = language ?? _language;
    final iMaxDistance = maxDistance ?? this.maxDistance;
    final iTerm = term.toLowerCase().trim();
    // Always (re)apply the language for correct namespace isolation
    // (see lookup for the rationale).
    store.setLanguage(iLanguage);

    var initialEntry = true;
    var entry = store.getEntry(iTerm);

    if (entry == null) {
      entry = DictionaryEntry(frequency);
    } else {
      final entryFrequency = entry[0];
      if (entryFrequency == 0) {
        entry[0] = frequency;
      } else {
        initialEntry = false;
      }
    }

    store.setEntry(iTerm, entry);
    if (initialEntry) {
      final number = store.pushTerm(iTerm) - 1;
      final deletes = _edits(iTerm, 0, iMaxDistance, <String>{});
      final deletesArray = deletes.toList(growable: false);
      final items = store.getEntries(deletesArray);

      for (var index = 0; index < items.length; index++) {
        final dKey = deletesArray[index];
        final item = items[index];
        if (item != null) {
          if (!item.contains(number)) {
            item.add(number);
            store.setEntry(dKey, item);
          }
        } else {
          store.setEntry(dKey, DictionaryEntry(0, <int>[number]));
        }
      }
    }
  }

  /// Trains on bulk data.
  ///
  /// Each item of [terms] is a comma separated value containing
  /// `term,frequency`.
  void train(List<String> terms, [String? language]) {
    _checkForReadiness();

    for (final line in terms) {
      if (line.isEmpty) {
        continue;
      }
      final parts = line.split(',');
      final term = parts[0];
      if (term.isEmpty) {
        continue;
      }
      final frequency = parts.length > 1 ? int.tryParse(parts[1]) ?? 1 : 1;
      add(term, frequency, language);
    }
  }

  /// Trains all terms of a parsed [Dictionary].
  void trainDictionary(Dictionary dictionary, [String? language]) {
    _checkForReadiness();

    for (final entry in dictionary.terms.entries) {
      add(entry.key, entry.value, language);
    }
  }

  /// Trains from a stream of `term,frequency` lines without ever holding
  /// the raw content or a [Dictionary] in memory — suitable for very large
  /// dictionaries (1M+ words) read incrementally.
  Future<void> trainLineStream(Stream<String> lines, [String? language]) async {
    _checkForReadiness();

    await for (final line in lines) {
      if (line.isEmpty) {
        continue;
      }
      final parts = line.split(',');
      final term = parts[0];
      if (term.isEmpty) {
        continue;
      }
      final frequency = parts.length > 1 ? int.tryParse(parts[1]) ?? 1 : 1;
      add(term, frequency, language);
    }
  }

  /// Trains from raw UTF-8 byte chunks (e.g. `File.openRead()` output).
  /// Multi-byte characters and lines split across chunk boundaries are
  /// handled correctly.
  Future<void> trainByteStream(Stream<List<int>> bytes, [String? language]) {
    return trainLineStream(
      bytes.transform(utf8.decoder).transform(const LineSplitter()),
      language,
    );
  }

  /// Whether [term] is a trained dictionary term (frequency > 0), i.e. the
  /// term is considered valid / correctly spelled.
  ///
  /// This is an O(1) exact membership check and also answers `false` for
  /// delete keys of other terms. Use a [Trie] instead when you don't need
  /// fuzzy suggestions and want a smaller memory footprint.
  bool hasTerm(String term, [String? language]) {
    _checkForReadiness();

    final iLanguage = language ?? _language;
    // Always (re)apply the language: unlike the `_language` instance field
    // (which only tracks the default), the store's current language must
    // follow the requested one for correct isolation.
    store.setLanguage(iLanguage);

    final entry = store.getEntry(term.toLowerCase().trim());
    return entry != null && entry.isNotEmpty && entry[0] > 0;
  }

  /// Exports every trained term of [language] (including words added at
  /// runtime via [add] / [trainDictionary]) with its current frequency.
  ///
  /// Only real terms are exported — delete keys are skipped. Serialize the
  /// result back to a file with [Dictionary.toLines] and re-train later
  /// with [trainDictionary] for a lossless round-trip.
  Dictionary exportDictionary([String? language]) {
    _checkForReadiness();

    final iLanguage = language ?? _language;
    store.setLanguage(iLanguage);

    final terms = <String, int>{};
    for (var i = 0; i < store.termCount; i++) {
      final term = store.getTermAt(i);
      if (term == null) {
        continue;
      }
      final entry = store.getEntry(term);
      terms[term] = entry != null && entry.isNotEmpty ? entry[0] : 1;
    }
    return Dictionary(terms);
  }

  /// Convenience alias for `exportDictionary(language).toLines()`
  /// (`term,frequency` records, most frequent first) — ready to write to a
  /// file with `File(...).writeAsString(lines.join('\n'))`.
  List<String> exportLines([String? language]) =>
      exportDictionary(language).toLines();

  /// Exports the trained dictionary of [language] as UTF-8 bytes in file
  /// format, ready for `File(...).writeAsBytes(speller.exportBytes())`.
  /// Re-import with [Dictionary.fromBytes] + [trainDictionary].
  Uint8List exportBytes([String? language]) =>
      exportDictionary(language).toBytes();

  /// Streams the trained dictionary of [language] as UTF-8 byte chunks
  /// (`term,frequency` per line), without materializing a [Dictionary]:
  ///
  /// ```dart
  /// await speller.exportStream(Languages.english)
  ///     .pipe(File('trained.txt').openWrite());
  /// ```
  ///
  /// Lines are batched (~512 per chunk) to keep the event count low.
  /// Note: lines are emitted in insertion order (streaming cannot sort by
  /// frequency without buffering); [exportBytes] sorts when needed.
  Stream<List<int>> exportStream([String? language]) async* {
    _checkForReadiness();

    final iLanguage = language ?? _language;
    store.setLanguage(iLanguage);

    const batchSize = 512;
    var buffer = StringBuffer();
    var count = 0;
    for (var i = 0; i < store.termCount; i++) {
      final term = store.getTermAt(i);
      if (term == null) {
        continue;
      }
      final entry = store.getEntry(term);
      final frequency = entry != null && entry.isNotEmpty ? entry[0] : 1;
      buffer
        ..write(term)
        ..write(',')
        ..write(frequency)
        ..write('\n');
      count++;
      if (count >= batchSize) {
        yield Uint8List.fromList(utf8.encode(buffer.toString()));
        buffer = StringBuffer();
        count = 0;
      }
    }
    if (count > 0) {
      yield Uint8List.fromList(utf8.encode(buffer.toString()));
    }
  }

  /// Alias for [lookup].
  List<Suggestion> search(
    String input,
    String language, [
    int? maxDistance,
    int? maxSuggestions,
  ]) {
    return lookup(
      input,
      language: language,
      maxDistance: maxDistance,
      maxSuggestions: maxSuggestions,
    );
  }

  /// Corrects every word token in [input] and returns the corrected output
  /// together with the per-token suggestions.
  Correction? correct(String? input, String language, [int? maxDistance]) {
    _checkForReadiness();
    if (input == null) {
      return null;
    }

    final iMaxDistance = maxDistance ?? this.maxDistance;
    final suggestions = <Suggestion>[];
    final tokens = _tokenizer.tokenize(input);
    final outputBuffer = StringBuffer();

    for (final token in tokens) {
      var term = token.value;
      var termSuggestion = Suggestion(term, null, 0, 0);
      final postDistance = token.distance;

      if (token.tag == TokenTags.word && token.value.length >= 2) {
        final lSuggestions = lookup(
          term,
          language: language,
          maxDistance: iMaxDistance,
          maxSuggestions: 1,
        );
        if (lSuggestions.isNotEmpty) {
          termSuggestion = lSuggestions.first;
        }
      }

      // Check word first char case.
      if (RegExp(r'^[A-Z]').hasMatch(token.value)) {
        final sTerm = termSuggestion.suggestion;
        if (sTerm != null && sTerm.isNotEmpty) {
          termSuggestion.suggestion =
              sTerm.substring(0, 1).toUpperCase() + sTerm.substring(1);
        }
      }

      suggestions.add(termSuggestion);
      term = termSuggestion.suggestion ?? termSuggestion.term;
      outputBuffer.write(term);
      if (postDistance > 0 && !term.endsWith(' ')) {
        outputBuffer.write(' ' * postDistance);
      }
    }

    return Correction(input, outputBuffer.toString(), suggestions);
  }

  void clear() {
    _checkForReadiness();
    store.clear();
  }
}
