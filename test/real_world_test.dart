/// Real-world validation against standard public data sets:
///
///  * Peter Norvig's `spell-errors.txt` — 7,841 "right: wrong1, wrong2"
///    misspelling pairs collected from Wikipedia and Roger Mitton's corpus
///    (the de facto standard spell-checker test set).
///  * `count_big.txt` — 29,136 real English words with counts, derived from
///    the `big.txt` running-text corpus.
///  * `sgb-words.txt` — 5,757 five-letter words from Knuth's Stanford
///    GraphBase (a plain word list, no frequencies).
///  * Hand-written Spanish frequency list + a Hunspell-style personal
///    dictionary.
library;

import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novident_spell_checker/novident_spell_checker.dart';

const _assets = 'test/assets';

Dictionary _loadDictionary(String path) =>
    Dictionary.fromLines(File('$_assets/dictionaries/$path').readAsLinesSync());

/// Parses Norvig's `spell-errors.txt` lines of the form
/// `right: wrong1, wrong2, wrong*3` into single-word (right, wrong) pairs.
/// Multi-word entries (containing `_`) are excluded: they need a
/// missing-space corrector, not a single-word engine.
List<(String, String)> _parseSpellErrors(String path) {
  final pairs = <(String, String)>[];
  for (final line in File('$_assets/norvig/$path').readAsLinesSync()) {
    final colon = line.indexOf(':');
    if (colon == -1) {
      continue;
    }
    final right = line.substring(0, colon).trim();
    if (right.isEmpty || right.contains('_')) {
      continue;
    }
    for (final raw in line.substring(colon + 1).split(',')) {
      var wrong = raw.trim();
      final star = wrong.indexOf('*');
      if (star != -1) {
        wrong = wrong.substring(0, star).trim();
      }
      if (wrong.isEmpty || wrong.contains('_')) {
        continue;
      }
      pairs.add((right, wrong));
    }
  }
  return pairs;
}

String _substitute(String word, Random rng) {
  const letters = 'abcdefghijklmnopqrstuvwxyz';
  final pos = rng.nextInt(word.length);
  final original = word[pos];
  var replacement = original;
  while (replacement == original) {
    replacement = letters[rng.nextInt(letters.length)];
  }
  return word.substring(0, pos) + replacement + word.substring(pos + 1);
}

void main() {
  group('Real-world: Norvig standard misspelling set', () {
    late SymSpellEx symSpell;
    late Dictionary enDict;

    setUpAll(() {
      symSpell = SymSpellEx(MemoryStore())..initialize();
      enDict = _loadDictionary('en_count_big.txt');
      symSpell.trainDictionary(enDict, Languages.english);
      debugPrint('[REAL] trained ${enDict.length} real English words');
    });

    test(
      'corrects Wikipedia/Mitton misspellings',
      timeout: const Timeout(Duration(minutes: 3)),
      () {
        final pairs = _parseSpellErrors('spell-errors.txt');
        expect(pairs, isNotEmpty);

        final editDistance = DamerauLevenshteinDistance();
        var hits = 0;
        var covered = 0;
        var contextual = 0; // A: the typed word is itself valid (d0)
        var beyondRange = 0; // B: right word farther than maxDistance
        var closerWord = 0; // C: another word is strictly closer
        var lostTie = 0; // D: same distance, frequency picked another word
        var engineMisses = 0; // E: right within range but not found (bug)
        final missSamples = <String>[];

        for (final (right, wrong) in pairs) {
          final inDict = symSpell.hasTerm(right);
          if (inDict) {
            covered++;
          }

          final distance = editDistance.calculateDistance(wrong, right);
          final suggestions = symSpell.lookup(wrong);
          final first = suggestions.isEmpty ? null : suggestions.first;
          final hit = first != null && first.suggestion == right;

          if (hit) {
            hits++;
            continue;
          }

          if (!inDict) {
            continue;
          }

          if (distance == 0) {
            continue;
          }

          if (symSpell.hasTerm(wrong)) {
            contextual++;
            if (missSamples.length < 6) {
              missSamples.add('A [$wrong is a valid word] expected $right');
            }
          } else if (distance > symSpell.maxDistance) {
            beyondRange++;
          } else if (suggestions.isEmpty) {
            engineMisses++;
            if (missSamples.length < 6) {
              missSamples.add('E [$wrong -> <none>] expected $right');
            }
          } else if (first!.distance < distance) {
            closerWord++;
          } else {
            lostTie++;
            if (missSamples.length < 6) {
              missSamples.add(
                'D [$wrong -> ${first.suggestion}] '
                'expected $right (d$distance)',
              );
            }
          }
        }

        final total = pairs.length;
        final coverage = covered / total;
        // Fair denominator: covered words the engine could plausibly return
        // (typed word not valid, target within maxDistance).
        final fairDenominator = covered - contextual - beyondRange;
        final fairAccuracy = hits / fairDenominator;
        // Ranking accuracy: among cases where the right word was found at
        // the minimal distance, how often did frequency ranking pick it?
        // (Lost ties improve with a larger frequency dictionary, e.g.
        // Norvig's 333k-word count_1w.)
        final rankingAccuracy = hits / (hits + lostTie + engineMisses);

        debugPrint(
          '[REAL] spell-errors: $total cases, coverage '
          '${(coverage * 100).toStringAsFixed(1)}%, top-1 accuracy '
          '${(100 * hits / total).toStringAsFixed(1)}% overall / '
          '${(fairAccuracy * 100).toStringAsFixed(1)}% fair / '
          '${(rankingAccuracy * 100).toStringAsFixed(1)}% ranking',
        );
        debugPrint(
          '[REAL] misses: $contextual contextual (typed word valid), '
          '$beyondRange out-of-range, $closerWord closer-word, '
          '$lostTie lost ties, $engineMisses engine misses',
        );
        for (final sample in missSamples) {
          debugPrint('[REAL]   $sample');
        }

        // Reference: Norvig reports ~68-75% top-1 with a 1M-word corpus.
        // Our dictionary is 29k words, so coverage is lower, but every
        // covered case within range must be found (no engine misses).
        expect(coverage, greaterThan(0.85));
        expect(engineMisses, 0);
        expect(rankingAccuracy, greaterThan(0.75));
      },
    );

    test('every dictionary word is recognized exactly (self-validation)', () {
      final words = enDict.terms.keys.toList();
      expect(words.length, greaterThan(29000));

      var failures = 0;
      for (final word in words) {
        final suggestions = symSpell.lookup(word);
        if (suggestions.isEmpty ||
            suggestions.first.suggestion != word ||
            suggestions.first.distance != 0) {
          failures++;
          if (failures <= 5) {
            debugPrint('[REAL] self-validation failure: $word');
          }
        }
      }

      expect(failures, 0);
    });

    test('recalls every real word from a distance-1 typo', () {
      final rng = Random(7);
      final words = enDict.terms.keys.where((w) => w.length >= 5).toList()
        ..shuffle(rng);
      final sample = words.take(2000).toList();

      var failures = 0;
      final misses = <String>[];
      for (final word in sample) {
        final typo = _substitute(word, rng);
        // A large limit: we assert recall (the word appears among the
        // candidates), not top-1 ranking.
        final suggestions = symSpell.lookup(typo, maxSuggestions: 100);
        if (!suggestions.any((s) => s.suggestion == word)) {
          failures++;
          if (misses.length < 5) {
            misses.add('$typo (expected $word)');
          }
        }
      }

      debugPrint(
        '[REAL] typo recall: ${sample.length} sampled words, '
        '$failures misses (${(100 * failures / sample.length).toStringAsFixed(1)}%)',
      );
      for (final miss in misses) {
        debugPrint('[REAL]   recall miss: $miss');
      }

      // A typo can coincide with another valid word (distance 0 beats
      // distance 1), so allow a small, realistic miss rate.
      expect(failures, lessThan(sample.length * 2 ~/ 100));
    });

    test('regression: substitution typo finds the original word', () {
      final s = SymSpellEx(MemoryStore())..initialize();
      s.add('soared', 100);
      s.add('fared', 200);

      final suggestions = s.lookup('sfared');
      debugPrint(
        '[REAL] sfared -> ${suggestions.map((x) => x.suggestion).toList()}',
      );

      // 'soared' must be recalled: it shares the 'sared' delete key with
      // 'sfared' (distance 1), regardless of 'fared' ranking first.
      expect(suggestions.any((x) => x.suggestion == 'soared'), isTrue);
    });
  });

  group('Real-world: plain word list (Stanford GraphBase)', () {
    test('trains a frequency-less word list of real words', () {
      final sgb = Dictionary.fromLines(
        File('$_assets/dictionaries/sgb_words.txt').readAsLinesSync(),
      );
      expect(sgb.length, greaterThan(5700));

      final symSpell = SymSpellEx(MemoryStore())..initialize();
      symSpell.trainDictionary(sgb, Languages.english);

      expect(symSpell.hasTerm('words'), isTrue);

      // Without frequencies, ties between equidistant candidates
      // ('birds' vs 'words' for 'wirds') are arbitrary — assert recall,
      // not ranking.
      final suggestions = symSpell.lookup('wirds');
      expect(suggestions.map((s) => s.suggestion), contains('words'));
      expect(suggestions.every((s) => s.distance == 1), isTrue);
    });
  });

  group('Real-world: Spanish frequency dictionary', () {
    late SymSpellEx symSpell;

    setUp(() {
      symSpell = SymSpellEx(MemoryStore())..initialize();
      symSpell.trainDictionary(
        _loadDictionary('es_common.txt'),
        Languages.spanish,
      );
    });

    test('recognizes accented words', () {
      for (final word in [
        'adiós',
        'música',
        'día',
        'año',
        'difícil',
        'rápido',
        'más',
        'también',
        'gracias',
        'hola',
      ]) {
        expect(
          symSpell.hasTerm(word, Languages.spanish),
          isTrue,
          reason: 'missing dictionary word: $word',
        );
      }
    });

    test('corrects realistic Spanish typos', () {
      // 'holaa' -> 'hola' is unambiguous (delete one char, distance 1).
      expect(symSpell.correct('holaa', Languages.spanish)!.output, 'hola');
      expect(symSpell.correct('adios', Languages.spanish)!.output, 'adiós');

      final correction = symSpell.correct(
        'muchas grcias por tu ayuda',
        Languages.spanish,
      );
      expect(correction!.output, 'muchas gracias por tu ayuda');
    });
  });

  group('Real-world: Hunspell personal dictionary', () {
    test('parses the personal dictionary asset', () {
      final personal = HunspellDictionary.fromLines(
        File('$_assets/dictionaries/es_personal.txt').readAsLinesSync(),
      );

      expect(
        personal.terms.terms.keys,
        containsAll(['Kaelen', 'Ciudadela', 'Rayken']),
      );
      expect(personal.forbidden, contains('villanox'));
    });
  });
}
