import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:novident_spell_checker/novident_spell_checker.dart';

import 'dictionary_test.dart';

void main() {
  group('HunspellDictionary', () {
    test('parses a main .dic with count header and flags', () {
      final dict = HunspellDictionary.fromLines([
        '3',
        'hello',
        'try/B',
        'work/AB',
      ]);

      expect(dict.terms.terms, {'hello': 1, 'try': 1, 'work': 1});
      expect(dict.flags, {'try': 'B', 'work': 'AB'});
      expect(dict.forbidden, isEmpty);
      expect(dict.pairs, isEmpty);
      expect(dict.length, 3);
    });

    test('parses a plain word list (valid Hunspell dictionary)', () {
      final dict = HunspellDictionary.fromLines(['hola', 'mundo']);

      expect(dict.terms.terms, {'hola': 1, 'mundo': 1});
    });

    test('handles escaped slashes inside words', () {
      final dict = HunspellDictionary.fromLines(['2', r'and\/or', 'yes/no']);

      expect(dict.terms.terms.keys, contains('and/or'));
      expect(dict.terms.terms.keys, contains('yes'));
      expect(dict.flags['yes'], 'no');
    });

    test('parses personal dictionaries (forbidden and example affixes)', () {
      final dict = HunspellDictionary.fromLines([
        'foo',
        'Foo/Simpson',
        '*bar',
        '*BAZ',
      ]);

      expect(dict.terms.terms.keys, containsAll(['foo', 'Foo']));
      expect(dict.forbidden, {'bar', 'baz'}); // normalized to lowercase
      expect(dict.flags['Foo'], 'Simpson');
    });

    test('parses multi-word pairs for missing-space corrections', () {
      final dict = HunspellDictionary.fromLines(['2', 'a lot', 'in spite']);

      expect(dict.pairs, ['a lot', 'in spite']);
      expect(dict.terms.isEmpty, isTrue);
    });

    test('strips a UTF-8 BOM and ignores empty lines', () {
      final dict = HunspellDictionary.fromLines([
        '\uFEFF3',
        '',
        'hello',
        '  ',
        'world/AB',
      ]);

      expect(dict.terms.terms, {'hello': 1, 'world': 1});
    });

    test('fromString splits records', () {
      final dict = HunspellDictionary.fromString('2\nhola\nmundo/A\n');

      expect(dict.terms.terms, {'hola': 1, 'mundo': 1});
    });

    test('toLines round-trips flags, pairs and forbidden words', () {
      final dict = HunspellDictionary.fromLines([
        '3',
        'hola',
        'try/B',
        'work/AB',
        'a lot',
        '*villanoX',
      ]);

      final exported = dict.toLines(includeCountHeader: true);
      final again = HunspellDictionary.fromLines(exported);

      expect(again.terms.terms, dict.terms.terms);
      expect(again.flags, {'try': 'B', 'work': 'AB'});
      expect(again.pairs, ['a lot']);
      expect(again.forbidden, {'villanox'});
    });

    test('toText produces writable file content', () {
      final dict = HunspellDictionary.fromLines(['2', 'hola', 'mundo/A']);

      final text = dict.toText();

      expect(text, contains('hola'));
      expect(text, contains('mundo/A'));
      expect(HunspellDictionary.fromString(text).terms.terms, dict.terms.terms);
    });

    test('toBytes round-trips flags, pairs and forbidden words', () {
      final dict = HunspellDictionary.fromLines([
        '3',
        'hola',
        'try/B',
        'work/AB',
        'a lot',
        '*villanoX',
      ]);

      final bytes = dict.toBytes(includeCountHeader: true);
      final again = HunspellDictionary.fromBytes(bytes);

      expect(again.terms.terms, dict.terms.terms);
      expect(again.flags, dict.flags);
      expect(again.pairs, dict.pairs);
      expect(again.forbidden, dict.forbidden);
    });
  });

  group('Hunspell dictionary workflow', () {
    test('trains terms and keeps forbidden words out', () {
      final dict = HunspellDictionary.fromLines([
        '2',
        'hola',
        'mundo/A',
        '*hola',
      ]);

      final symSpell = SymSpellEx(MemoryStore())..initialize();
      symSpell.trainDictionary(dict.terms);

      expect(symSpell.hasTerm('hola'), isTrue);
      expect(symSpell.hasTerm('mundo'), isTrue);

      // Forbidden words are never trained; check them explicitly.
      expect(dict.forbidden.contains('hola'), isTrue);
    });

    test('loadHunspell reads an asset bundle', () async {
      final bundle = FakeAssetBundle({
        'assets/dictionaries/es.dic': '3\nhola\nmundo/A\ntrabajo/AB\n',
      });

      final dict = await AssetDictionaryLoader.loadHunspell(
        'assets/dictionaries/es.dic',
        bundle: bundle,
      );

      expect(dict.terms.terms.keys, containsAll(['hola', 'mundo', 'trabajo']));
      expect(dict.flags, {'mundo': 'A', 'trabajo': 'AB'});
    });
  });

  group('Hunspell streaming', () {
    test('fromByteStream handles chunked .dic input', () async {
      final text = '3\nhola\ntry/B\nwork/AB\na lot\n*villanoX\n';
      final bytes = Uint8List.fromList(utf8.encode(text));

      for (final chunkSize in const [1, 2]) {
        final dict = await HunspellDictionary.fromByteStream(
          _hChunked(bytes, chunkSize),
        );
        expect(
            dict.terms.terms,
            {
              'hola': 1,
              'try': 1,
              'work': 1,
            },
            reason: 'chunk size $chunkSize');
        expect(dict.flags, {'try': 'B', 'work': 'AB'});
        expect(dict.pairs, ['a lot']);
        expect(dict.forbidden, {'villanox'});
      }
    });

    test('toByteStream round-trips', () async {
      final dict = HunspellDictionary.fromLines(['2', 'hola', 'mundo/A']);

      final collected = await _hCollect(dict.toByteStream());
      final again = await HunspellDictionary.fromByteStream(
        Stream.value(collected),
      );

      expect(again.terms.terms, dict.terms.terms);
      expect(again.flags, dict.flags);
    });
  });
}

Stream<List<int>> _hChunked(Uint8List data, int chunkSize) async* {
  for (var i = 0; i < data.length; i += chunkSize) {
    final end = (i + chunkSize) < data.length ? i + chunkSize : data.length;
    yield data.sublist(i, end);
  }
}

Future<Uint8List> _hCollect(Stream<List<int>> stream) async {
  final builder = BytesBuilder();
  await for (final chunk in stream) {
    builder.add(chunk);
  }
  return builder.takeBytes();
}
