/// Regression tests for the whitespace-handling bugs reported in the
/// editor:
///
///  * With heavy/mixed whitespace, tokens lose the surrounding spaces, so
///    rebuilding the text truncates it and offsets drift (misspelled-word
///    underlines land on the wrong range, e.g. "ing Elara" instead of
///    "Elara").
///  * Word tokens visually merge when separated by newlines/tabs (the old
///    distance heuristic only detects single ASCII spaces).
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:novident_spell_checker/novident_spell_checker.dart';

const _assets = 'test/assets';

/// Rebuilds text from tokens using the exact-spacing API
/// (`value` + `spacing`) — the same way the editor reconstructs spans and
/// offsets.
String _rebuild(List<Token> tokens) =>
    tokens.map((t) => t.value + t.spacing).join();

List<String> _wordTokens(String input) => CoreTokenizer()
    .tokenize(input)
    .where((t) => t.tag == TokenTags.word)
    .map((t) => t.value)
    .toList();

void main() {
  final tokenizer = CoreTokenizer();

  group('CoreTokenizer: whitespace preservation (regression)', () {
    test('keeps word tokens separate across heavy whitespace', () {
      expect(_wordTokens('The  thing   Elara'), ['The', 'thing', 'Elara']);
      expect(_wordTokens('thing\nElara'), ['thing', 'Elara']);
      expect(_wordTokens('thing\tElara'), ['thing', 'Elara']);
    });

    test('rebuilds the exact original text (lossless round-trip)', () {
      const inputs = [
        'The  thing   Elara',
        'hello   world',
        '  leading spaces',
        'trailing spaces   ',
        'thing\nElara',
        'thing\tElara',
        'a\n\nb',
        'word \u00A0 word', // non-breaking space
        'word \u00A0\u00A0word', // repeated non-breaking spaces
        'a \tb\n',
      ];

      for (final input in inputs) {
        final tokens = tokenizer.tokenize(input);
        expect(_rebuild(tokens), input, reason: 'input: "$input"');
      }
    });

    test('locates words at their exact original offsets', () {
      const input = 'The  thing   Elara moved';
      final tokens = tokenizer.tokenize(input);
      final rebuilt = _rebuild(tokens);

      // An editor maps misspelled-word ranges from the rebuilt text back
      // to the original document; any drift underlines the wrong range
      // (the reported "ing Elara" symptom).
      expect(rebuilt.indexOf('Elara'), input.indexOf('Elara'),
          reason: 'offset drift for Elara');
      expect(rebuilt.indexOf('thing'), input.indexOf('thing'));
      expect(rebuilt.indexOf('moved'), input.indexOf('moved'));

      // Every token carries its exact start offset in the source text.
      for (final token in tokens) {
        expect(token.offset, input.indexOf(token.value, token.offset),
            reason: 'token "${token.value}" offset mismatch');
      }
    });

    test('flags exactly the misspelled word (editor scenario)', () {
      final symSpell = SymSpellEx(MemoryStore())..initialize();
      for (final word in ['the', 'thing', 'moved']) {
        symSpell.add(word, 10);
      }

      const input = 'The  thing   Elara moved';
      final flagged = <String>[];
      final rebuiltParts = <String>[];
      for (final token in tokenizer.tokenize(input)) {
        if (token.tag == TokenTags.word &&
            token.value.length >= 2 &&
            !symSpell.hasTerm(token.value)) {
          flagged.add(token.value);
        }
        rebuiltParts.add(token.value + token.spacing);
      }
      final rebuilt = rebuiltParts.join();

      expect(flagged, ['Elara']);
      expect(rebuilt.indexOf('Elara'), input.indexOf('Elara'),
          reason: 'misspelled word range drifted');
    });

    test('works against the real en_US dictionary (stems)', () {
      final symSpell = SymSpellEx(MemoryStore())..initialize();
      final dictionary = HunspellDictionary.fromLines(
        File('$_assets/dictionaries/en_US.dic').readAsLinesSync(),
      );
      symSpell.trainDictionary(dictionary.terms, Languages.english);

      const input = 'The  thing   Elara';
      final flagged = <String>[];
      for (final token in tokenizer.tokenize(input)) {
        if (token.tag == TokenTags.word &&
            token.value.length >= 2 &&
            !symSpell.hasTerm(token.value, Languages.english)) {
          flagged.add(token.value);
        }
      }

      expect(flagged, ['Elara']);
    });
  });
}
