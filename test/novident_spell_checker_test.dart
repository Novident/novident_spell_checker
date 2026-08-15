import 'package:flutter_test/flutter_test.dart';
import 'package:novident_spell_checker/novident_spell_checker.dart';

const enValidTerms = [
  'albert',
  'argument',
  'academically',
  'groundbreaking',
  'Electrodynamics',
];

const enSentence =
    'In 1905, a year sometimes described as his annus mirabilis (miracle year), '
    'Einstein published four groundbreaking papers.';

void main() {
  late MemoryStore store;

  setUp(() {
    store = MemoryStore();
  });

  group('SymSpellEx instance creation', () {
    test('is initialized after initialize()', () {
      final symSpellEx = SymSpellEx(store);
      expect(symSpellEx.isInitialized(), isFalse);

      symSpellEx.initialize();
      expect(symSpellEx.isInitialized(), isTrue);
    });

    test('throws before initialization', () {
      final symSpellEx = SymSpellEx(store);
      expect(
        () => symSpellEx.clear(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'SymSpellEx must be initialized, Please call initialize() first',
          ),
        ),
      );
    });

    test('constructor accepts custom edit distance and limits', () {
      const maxDistance = 3;
      const maxSuggestions = 10;

      final symSpellEx = SymSpellEx(
        store,
        editDistance: DamerauLevenshteinDistance(),
        tokenizer: CoreTokenizer(),
        maxDistance: maxDistance,
        maxSuggestions: maxSuggestions,
      );
      symSpellEx.initialize();

      for (final term in enValidTerms) {
        symSpellEx.add(term, 1, Languages.english);
      }

      final correction = symSpellEx.correct('acaddemqicaly', Languages.english);

      expect(symSpellEx.editDistance, isA<DamerauLevenshteinDistance>());
      expect(symSpellEx.maxDistance, maxDistance);
      expect(symSpellEx.maxSuggestions, maxSuggestions);

      expect(correction, isNotNull);
      expect(correction!.suggestions, hasLength(1));
      expect(correction.suggestions[0].distance, 3);
      expect(correction.suggestions[0].suggestion, 'academically');
    });
  });

  group('CoreTokenizer', () {
    test('tokenizes a full sentence', () {
      final tokenizer = CoreTokenizer();
      final tokens = tokenizer.tokenize(enSentence);

      expect(tokens, hasLength(22));
      expect(tokens[21].value, '.');
      expect(tokens[21].tag, TokenTags.punctuation);
    });

    test('tokenizes numbers and words with distances', () {
      final tokenizer = CoreTokenizer();
      final tokens = tokenizer.tokenize('hello, world');

      // The comma part recurses: the untagged ', ' token is re-tokenized.
      // Note: ',' is not in the latin punctuation class of the original
      // symspell-ex tokenizer, so it keeps the fallback 'none' tag.
      expect(tokens.map((t) => t.value).toList(), ['hello', ',', 'world']);
      expect(tokens[0].tag, TokenTags.word);
      expect(tokens[1].tag, TokenTags.none);
      expect(tokens[1].distance, 1);
      expect(tokens[0].distance, 0);
    });

    test('returns empty list for empty input', () {
      expect(CoreTokenizer().tokenize(''), isEmpty);
    });
  });

  group('SymSpellEx basic corrections', () {
    late SymSpellEx symSpellEx;

    setUp(() {
      symSpellEx = SymSpellEx(store);
      symSpellEx.initialize();
      for (final term in enValidTerms) {
        symSpellEx.add(term, 1, Languages.english);
      }
    });

    test('corrects known words with distance 0', () {
      final sNormal = symSpellEx.correct('academically', Languages.english);
      final sCase = symSpellEx.correct('Academically', Languages.english);

      expect(sNormal, isNotNull);
      expect(sCase, isNotNull);
      expect(sNormal!.suggestions, hasLength(1));
      expect(sCase!.suggestions, hasLength(1));
      expect(sNormal.suggestions[0].distance, 0);
      expect(sCase.suggestions[0].distance, 0);
      expect(sNormal.output, isNot(sCase.output));
      expect(sNormal.output, sCase.output.toLowerCase());
      expect(sCase.output, 'Academically');
    });

    test('corrects a full sentence', () {
      final correction = symSpellEx.correct(
        'albrt did groundbrekin academicaly work.',
        Languages.english,
      );

      expect(correction, isNotNull);
      final words = correction!.suggestions
          .where((s) => s.distance > 0)
          .map((s) => s.suggestion)
          .toList();
      expect(words, containsAll(['albert', 'groundbreaking', 'academically']));
      expect(correction.output, 'albert did groundbreaking academically work.');
    });
  });

  group('SymSpellEx lookup & fuzzy search', () {
    late SymSpellEx symSpellEx;

    setUp(() {
      symSpellEx = SymSpellEx(store);
      symSpellEx.initialize();
      for (final term in enValidTerms) {
        symSpellEx.add(term, 1, Languages.english);
      }
    });

    test('finds close matches with correct distance', () {
      final suggestions = symSpellEx.lookup('abart');

      expect(suggestions, isNotEmpty);
      expect(suggestions.first.suggestion, 'albert');
      expect(suggestions.first.distance, 2);
    });

    test('ranks by frequency at equal distance', () {
      // 'must', 'bust' and 'rust' all share the delete key 'ust'
      // (distance 1 from 'dust'). None collide with the setUp terms.
      symSpellEx.add('must', 9);
      symSpellEx.add('bust', 4);
      symSpellEx.add('rust', 1);

      final suggestions = symSpellEx.lookup('dust');

      expect(suggestions, hasLength(3));
      expect(suggestions.map((s) => s.suggestion).toList(), [
        'must',
        'bust',
        'rust',
      ]);
      expect(suggestions.map((s) => s.frequency).toList(), [9, 4, 1]);
    });

    test('respects maxSuggestions', () {
      symSpellEx.add('must', 9);
      symSpellEx.add('bust', 4);
      symSpellEx.add('rust', 1);

      final suggestions = symSpellEx.lookup('dust', maxSuggestions: 2);

      expect(suggestions, hasLength(2));
      expect(suggestions.map((s) => s.suggestion).toList(), ['must', 'bust']);
    });

    test('returns empty when term is too long for max distance', () {
      final suggestions = symSpellEx.lookup(
        'extraordinarilylongword',
        maxDistance: 2,
      );

      expect(suggestions, isEmpty);
    });
  });

  group('SymSpellEx add / train', () {
    late SymSpellEx symSpellEx;

    setUp(() {
      symSpellEx = SymSpellEx(store);
      symSpellEx.initialize();
    });

    test('accepts one-character terms (exact match only)', () {
      symSpellEx.add('a', 100);
      symSpellEx.add('I', 90);

      expect(symSpellEx.hasTerm('a'), isTrue);
      expect(symSpellEx.hasTerm('I'), isTrue);

      final suggestions = symSpellEx.lookup('a');
      expect(suggestions, isNotEmpty);
      expect(suggestions.first.suggestion, 'a');
      expect(suggestions.first.distance, 0);
    });

    test('ignores empty terms', () {
      symSpellEx.add('');
      expect(symSpellEx.lookup(''), isEmpty);
    });

    test('ignores empty lines in train', () {
      symSpellEx.train(const ['', 'albert,5', '   ', 'groundbreaking,2']);

      final suggestions = symSpellEx.lookup('albert');
      expect(suggestions, isNotEmpty);
      expect(suggestions.first.frequency, 5);
    });

    test('trains bulk terms with frequencies', () {
      symSpellEx.train(const ['albert,5', 'groundbreaking,2']);

      final albert = symSpellEx.lookup('albert');
      expect(albert.first.frequency, 5);

      final gb = symSpellEx.lookup('groundbreakin');
      expect(gb.first.suggestion, 'groundbreaking');
      expect(gb.first.distance, 1);
    });

    test('does not duplicate delete-key indexes on re-add', () {
      symSpellEx.add('albert');
      symSpellEx.add('albart');
      // 'abrt' is a shared delete key: [frequency, albertIdx, albartIdx].
      expect(store.getEntry('abrt'), hasLength(3));

      // Re-adding an existing term must not append its index again.
      symSpellEx.add('albert');

      final entry = store.getEntry('abrt');
      expect(entry, hasLength(3));
      expect(entry![0], 0);
    });
  });

  group('SymSpellEx Arabic', () {
    late SymSpellEx symSpellEx;

    setUp(() {
      symSpellEx = SymSpellEx(store);
      symSpellEx.initialize();
      for (final term in const ['ممتاز', 'انحسار', 'الاختصارات']) {
        symSpellEx.add(term, 1, Languages.arabic);
      }
    });

    test('corrects arabic words', () {
      final correction = symSpellEx.correct('ممتاد', Languages.arabic);

      expect(correction, isNotNull);
      expect(correction!.suggestions, hasLength(1));
      expect(correction.suggestions.first.suggestion, 'ممتاز');
      // د -> ز is a single substitution.
      expect(correction.suggestions.first.distance, 1);
    });

    test('keeps languages isolated', () {
      final arabic = symSpellEx.lookup('ممتاد', language: Languages.arabic);
      final english = symSpellEx.lookup('abart', language: Languages.english);

      expect(arabic, isNotEmpty);
      expect(english, isEmpty);
    });
  });

  group('SymSpellEx clear', () {
    test('removes all entries', () {
      final symSpellEx = SymSpellEx(store);
      symSpellEx.initialize();
      symSpellEx.add('albert');

      expect(symSpellEx.lookup('albert'), isNotEmpty);

      symSpellEx.clear();
      expect(symSpellEx.lookup('albert'), isEmpty);
    });
  });

  group('DamerauLevenshteinDistance', () {
    final editDistance = DamerauLevenshteinDistance();

    test('computes known distances', () {
      expect(editDistance.calculateDistance('', ''), 0);
      expect(editDistance.calculateDistance('', 'abc'), 3);
      expect(editDistance.calculateDistance('abc', ''), 3);
      expect(editDistance.calculateDistance('kitten', 'sitting'), 3);
      expect(editDistance.calculateDistance('ab', 'ba'), 1); // transposition
      expect(
        editDistance.calculateDistance('academically', 'acaddemqicaly'),
        3,
      );
    });
  });
}
