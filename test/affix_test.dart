import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novident_spell_checker/novident_spell_checker.dart';

import 'dictionary_test.dart' show FakeAssetBundle;

const _assets = 'test/assets';

/// The exact example from the Hunspell manual.
const _manualAff = '''
PFX A Y 1
PFX A 0 re .

SFX B Y 2
SFX B 0 ed [^y]
SFX B y ied y
''';

void main() {
  group('AffixRules (Hunspell manual example)', () {
    final affix = AffixRules.fromString(_manualAff);

    test('expands work/AB with cross products', () {
      expect(
        affix.expand('work', 'AB'),
        {'work', 'worked', 'rework', 'reworked'},
      );
    });

    test('expands try/B with the -yied rule', () {
      expect(affix.expand('try', 'B'), {'try', 'tried'});
    });

    test('flag splitting (single-char default)', () {
      expect(affix.splitFlags('AB'), ['A', 'B']);
    });
  });

  group('AffixRules (cross product control)', () {
    test('cross=N disables prefix+suffix combinations', () {
      final affix = AffixRules.fromString('''
PFX P N 1
PFX P 0 pre .

SFX S N 1
SFX S 0 s .
''');

      expect(affix.expand('word', 'PS'), {'word', 'preword', 'words'});
    });

    test('cross=Y enables prefix+suffix combinations', () {
      final affix = AffixRules.fromString('''
PFX P Y 1
PFX P 0 pre .

SFX S Y 1
SFX S 0 s .
''');

      expect(
          affix.expand('word', 'PS'), {'word', 'preword', 'words', 'prewords'});
    });
  });

  group('AffixRules (continuation classes)', () {
    // The twofold-suffix example from the Hunspell manual.
    final affix = AffixRules.fromString('''
SFX Y Y 1
SFX Y 0 s .

SFX X Y 1
SFX X 0 able/Y .
''');

    test('drink/X generates drink, drinkable, drinkables', () {
      expect(affix.expand('drink', 'X'), {'drink', 'drinkable', 'drinkables'});
    });
  });

  group('AffixRules (multi-char conditions)', () {
    final affix = AffixRules.fromString('''
SFX A Y 2
SFX A bir pción/S [^ch]ibir
SFX A ibir epción/S cibir
SFX S Y 1
SFX S 0 s .
''');

    test('escribir -> escripción', () {
      expect(affix.expand('escribir', 'A'), contains('escripción'));
    });

    test('percibir -> percepción (cibir rule)', () {
      expect(affix.expand('percibir', 'A'), contains('percepción'));
      expect(affix.expand('percibir', 'A'), isNot(contains('percipción')));
    });

    test('continuation S applies to the derived noun', () {
      // Rule-driven: this synthetic S rule appends plain 's' unconditionally.
      final forms = affix.expand('escribir', 'A');
      expect(forms, containsAll(['escribir', 'escripción', 'escripcións']));
    });
  });

  group('AffixRules (flag types)', () {
    test('FLAG long uses two-char flags', () {
      final affix = AffixRules.fromString('''
FLAG long
SFX Y1 Y 1
SFX Y1 0 s .
''');
      expect(affix.splitFlags('Y1Z3'), ['Y1', 'Z3']);
      expect(affix.expand('foo', 'Y1'), {'foo', 'foos'});
    });

    test('FLAG num uses comma-separated numeric flags', () {
      final affix = AffixRules.fromString('''
FLAG num
SFX 65000 Y 1
SFX 65000 0 s .
''');
      expect(affix.splitFlags('65000,12'), ['65000', '12']);
      expect(affix.expand('foo', '65000'), {'foo', 'foos'});
    });

    test('FLAG UTF-8 splits by code point', () {
      final affix =
          AffixRules.fromString('FLAG UTF-8\nSFX R Y 1\nSFX R r mos [aei]r\n');
      expect(affix.splitFlags('RED'), ['R', 'E', 'D']);
      expect(affix.expand('trabajar', 'R'), contains('trabajamos'));
    });
  });

  group('AffixRules (real dictionaries)', () {
    test('en_US: work and try generate real forms', () {
      final affix = AffixRules.fromString(
          File('$_assets/dictionaries/en_US.aff').readAsStringSync());

      final work = affix.expand('work', 'ADJSG');
      debugPrint('[AFFIX] work/ADJSG -> $work');
      expect(work, containsAll(['work', 'worked', 'rework', 'reworked']));

      final tryForms = affix.expand('try', 'AGDS');
      debugPrint('[AFFIX] try/AGDS -> $tryForms');
      expect(tryForms, containsAll(['try', 'tried', 'tries']));
    });

    test('es_ES: expands the full dictionary to many more forms', () {
      final dictionary = HunspellDictionary.fromLines(
        File('$_assets/dictionaries/es_ES.dic').readAsLinesSync(),
      );
      final affix = AffixRules.fromString(
          File('$_assets/dictionaries/es_ES.aff').readAsStringSync());

      final expanded = dictionary.expand(affix);
      final ratio = expanded.length / dictionary.length;
      debugPrint(
        '[AFFIX] es_ES: ${dictionary.length} stems -> '
        '${expanded.length} forms (${ratio.toStringAsFixed(1)}x)',
      );

      expect(expanded.length, greaterThan(dictionary.length * 2));

      // Real Spanish forms generated from stems.
      expect(expanded.terms.containsKey('trabajamos'), isTrue);
      expect(expanded.terms.containsKey('trabajar'), isTrue);
      // categorizar/AREDÀÁ → SFX A r ción/S ar → categorización,
      // then SFX S ón ones ón → categorizaciones.
      expect(expanded.terms.containsKey('categorización'), isTrue);
      expect(expanded.terms.containsKey('categorizaciones'), isTrue);

      // Flagged stems produce forms only when the .aff is applied:
      // without expansion these would be missing (that's the optional
      // behavior this feature enables).
      final sinAffix = dictionary.terms.terms;
      expect(sinAffix.containsKey('trabajamos'), isFalse);
    });
  });

  group('AffixRules I/O', () {
    test('fromBytes and fromByteStream parse chunked .aff content', () async {
      final bytes = Uint8List.fromList(utf8.encode(_manualAff));

      final a = AffixRules.fromBytes(bytes);
      final b = await AffixRules.fromByteStream(_chunks(bytes, 2));

      expect(a.expand('work', 'AB'), {'work', 'worked', 'rework', 'reworked'});
      expect(b.expand('work', 'AB'), a.expand('work', 'AB'));
    });

    test('loadHunspellWithAffixes loads and expands an asset pair', () async {
      final bundle = FakeAssetBundle({
        'assets/dic': '2\nwork/AB\ntry/B\n',
        'assets/aff': _manualAff,
      });

      final dict = await AssetDictionaryLoader.loadHunspellWithAffixes(
        'assets/dic',
        'assets/aff',
        bundle: bundle,
      );

      expect(
        dict.terms.keys,
        containsAll(['work', 'worked', 'rework', 'reworked', 'try', 'tried']),
      );
    });
  });
}

Stream<List<int>> _chunks(Uint8List data, int size) async* {
  for (var i = 0; i < data.length; i += size) {
    final end = (i + size) < data.length ? i + size : data.length;
    yield data.sublist(i, end);
  }
}
