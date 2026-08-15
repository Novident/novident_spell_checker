import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novident_spell_checker/novident_spell_checker.dart';

/// Minimal in-memory asset bundle for testing asset loaders.
class FakeAssetBundle extends AssetBundle {
  FakeAssetBundle(this._assets);

  final Map<String, String> _assets;

  @override
  Future<ByteData> load(String key) async {
    final data = _assets[key];
    if (data == null) {
      throw Exception('Unable to load asset: $key');
    }
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(data)));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Dictionary', () {
    test('parses the symspell-ex comma format', () {
      final dict = Dictionary.fromLines(['hello,5', 'world,2', '']);

      expect(dict.terms, {'hello': 5, 'world': 2});
      expect(dict.length, 2);
    });

    test('parses the Wolf Garbe whitespace format', () {
      final dict = Dictionary.fromLines(['hello 5', 'world   2']);

      expect(dict.terms, {'hello': 5, 'world': 2});
    });

    test('accepts plain word lists with frequency 1', () {
      final dict = Dictionary.fromLines(['hello', 'world']);

      expect(dict.terms, {'hello': 1, 'world': 1});
    });

    test('skips comments and malformed records', () {
      final dict = Dictionary.fromLines([
        '# comment',
        'hello,5',
        'world xyz',
        '',
        '   ',
      ]);

      expect(dict.terms, {'hello': 5});
    });

    test('fromCsv splits a single string', () {
      final dict = Dictionary.fromCsv('hello,5\nworld,2\n');

      expect(dict.terms, {'hello': 5, 'world': 2});
    });

    test('toLines round-trips and sorts by frequency desc', () {
      final dict = Dictionary.fromMap({'rare': 1, 'common': 9});

      final lines = dict.toLines();
      expect(lines.first, 'common,9');

      final again = Dictionary.fromLines(lines);
      expect(again.terms, dict.terms);
    });
  });

  group('Export & round-trip', () {
    test('exportDictionary writes runtime-learned words back to a file', () {
      final symSpell = SymSpellEx(MemoryStore())..initialize();
      symSpell.trainDictionary(Dictionary.fromLines(['hello,5', 'world,2']));

      // The dictionary "learns" new words at runtime.
      symSpell.add('kaelen', 7);
      symSpell.add('ciudadela', 1);

      // Export as the same kind of file it came from.
      final exported = symSpell.exportLines();
      final fileContent = exported.join('\n');

      // Re-import into a fresh instance: lossless round-trip.
      final reloaded = SymSpellEx(MemoryStore())..initialize();
      reloaded.trainDictionary(Dictionary.fromLines(fileContent.split('\n')));

      final dict = reloaded.exportDictionary();
      expect(dict.terms, {'kaelen': 7, 'hello': 5, 'world': 2, 'ciudadela': 1});
      expect(reloaded.hasTerm('kaelen'), isTrue);
    });

    test('exportDictionary is language-isolated', () {
      final symSpell = SymSpellEx(MemoryStore())..initialize();
      symSpell.add('hola', 5, Languages.spanish);
      symSpell.add('hello', 3, Languages.english);

      final spanish = symSpell.exportDictionary(Languages.spanish);
      final english = symSpell.exportDictionary(Languages.english);

      expect(spanish.terms.keys, contains('hola'));
      expect(spanish.terms.keys, isNot(contains('hello')));
      expect(english.terms.keys, contains('hello'));
      expect(english.terms.keys, isNot(contains('hola')));
    });

    test('export skips delete keys', () {
      final symSpell = SymSpellEx(MemoryStore())..initialize();
      symSpell.add('albert', 5);

      final dict = symSpell.exportDictionary();

      expect(dict.terms, {'albert': 5});
      // 'albrt' exists in the store as a delete key but is not exported.
      expect(dict.terms.containsKey('albrt'), isFalse);
    });

    test('toBytes round-trips through an actual file', () {
      final dir = Directory.systemTemp.createTempSync('spell_dict_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/personal.txt');

      // Learn at runtime, then persist with a one-liner.
      final symSpell = SymSpellEx(MemoryStore())..initialize();
      symSpell.add('kaelen', 7);
      symSpell.add('ciudadela', 3);
      file.writeAsBytesSync(symSpell.exportBytes());

      // Reload from the file with the matching one-liner.
      final reloaded = Dictionary.fromBytes(file.readAsBytesSync());
      expect(reloaded.terms, {'kaelen': 7, 'ciudadela': 3});

      // Byte-level round-trip is stable.
      final dict = Dictionary.fromMap({'b': 2, 'a': 5});
      final again = Dictionary.fromBytes(dict.toBytes());
      expect(again.terms, dict.terms);
    });
  });

  group('SymSpellEx.trainDictionary', () {
    test('trains a parsed dictionary with frequencies', () {
      final symSpell = SymSpellEx(MemoryStore())..initialize();
      symSpell.trainDictionary(Dictionary.fromLines(['hello,5', 'world,2']));

      final exact = symSpell.lookup('hello');
      expect(exact, isNotEmpty);
      expect(exact.first.frequency, 5);

      final typo = symSpell.lookup('hollo');
      expect(typo.first.suggestion, 'hello');
      expect(typo.first.distance, 1);
    });

    test('respects an explicit language', () {
      final symSpell = SymSpellEx(MemoryStore())..initialize();
      symSpell.trainDictionary(
        Dictionary.fromMap({'ممتاز': 5}),
        Languages.arabic,
      );

      final correction = symSpell.correct('ممتاد', Languages.arabic);

      expect(correction, isNotNull);
      expect(correction!.suggestions.first.suggestion, 'ممتاز');
    });
  });

  group('AssetDictionaryLoader', () {
    test('loads and parses a dictionary from an asset bundle', () async {
      final bundle = FakeAssetBundle({
        'assets/dictionaries/en.txt': 'hello,5\nworld,2\n',
      });

      final dict = await AssetDictionaryLoader.load(
        'assets/dictionaries/en.txt',
        bundle: bundle,
      );

      expect(dict.terms, {'hello': 5, 'world': 2});
    });

    test('loads whitespace-separated frequency files', () async {
      final bundle = FakeAssetBundle({
        'assets/dictionaries/freq.txt': 'the 2313585\nof 1315197\n',
      });

      final dict = await AssetDictionaryLoader.load(
        'assets/dictionaries/freq.txt',
        bundle: bundle,
      );

      expect(dict.terms, {'the': 2313585, 'of': 1315197});
    });
  });

  group('Streaming I/O', () {
    test('fromLineStream matches fromLines', () async {
      final lines = ['hello,5', 'world,2', '', 'adiós,3', '# comment'];

      final a = Dictionary.fromLines(lines);
      final b = await Dictionary.fromLineStream(Stream.fromIterable(lines));

      expect(b.terms, a.terms);
    });

    test(
      'fromByteStream handles tiny chunks and multi-byte characters',
      () async {
        // 'adiós' and 'música' contain 2-byte UTF-8 sequences; 1-2 byte
        // chunks force splits in the middle of characters and lines.
        final text = 'adiós,3\nmúsica,4\nhola,1\n';
        final bytes = Uint8List.fromList(utf8.encode(text));

        for (final chunkSize in const [1, 2, 3]) {
          final dict = await Dictionary.fromByteStream(
            _chunked(bytes, chunkSize),
          );
          expect(dict.terms, {
            'adiós': 3,
            'música': 4,
            'hola': 1,
          }, reason: 'chunk size $chunkSize');
        }
      },
    );

    test('toByteStream round-trips through fromByteStream', () async {
      final dict = Dictionary.fromMap({'adiós': 3, 'hola': 1, 'música': 4});

      final reloaded = await Dictionary.fromByteStream(
        _chunked(await _collectBytes(dict.toByteStream()), 3),
      );

      expect(reloaded.terms, dict.terms);
    });

    test('trainByteStream trains without materializing a Dictionary', () async {
      final symSpell = SymSpellEx(MemoryStore())..initialize();
      final text = 'hola,5\nmundo,2\nadiós,3\n';

      await symSpell.trainByteStream(
        _chunked(Uint8List.fromList(utf8.encode(text)), 2),
        Languages.spanish,
      );

      expect(symSpell.hasTerm('hola', Languages.spanish), isTrue);
      expect(symSpell.hasTerm('adiós', Languages.spanish), isTrue);
      expect(
        symSpell.lookup('hola', language: Languages.spanish).first.frequency,
        5,
      );
    });

    test('exportStream pipes to a file and reloads', () async {
      final dir = Directory.systemTemp.createTempSync('spell_stream_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/exported.txt');

      final symSpell = SymSpellEx(MemoryStore())..initialize();
      symSpell.add('kaelen', 7);
      symSpell.add('ciudadela', 3);

      await symSpell.exportStream().pipe(file.openWrite());

      final dict = Dictionary.fromBytes(file.readAsBytesSync());
      expect(dict.terms, {'kaelen': 7, 'ciudadela': 3});
    });
  });
}

/// Splits [data] into fixed-size chunks (the last one may be smaller).
Stream<List<int>> _chunked(Uint8List data, int chunkSize) async* {
  for (var i = 0; i < data.length; i += chunkSize) {
    final end = (i + chunkSize) < data.length ? i + chunkSize : data.length;
    yield data.sublist(i, end);
  }
}

Future<Uint8List> _collectBytes(Stream<List<int>> stream) async {
  final builder = BytesBuilder();
  await for (final chunk in stream) {
    builder.add(chunk);
  }
  return builder.takeBytes();
}
