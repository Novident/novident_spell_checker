import 'package:flutter_test/flutter_test.dart';
import 'package:novident_spell_checker/novident_spell_checker.dart';

void main() {
  group('Trie', () {
    test('insert and contains', () {
      final trie = Trie();
      expect(trie.contains('hello'), isFalse);

      trie.insert('hello');

      expect(trie.contains('hello'), isTrue);
      expect(trie.contains('hell'), isFalse); // prefix is not a word
      expect(trie.contains(''), isFalse);
      expect(trie.size, 1);
    });

    test('shares prefixes and deduplicates', () {
      final trie = Trie();
      trie.insert('car');
      trie.insert('card');
      trie.insert('care');
      trie.insert('car'); // duplicate

      expect(trie.size, 3);
      expect(trie.nodeCount, lessThan(10));
    });

    test('withPrefix returns words in lexicographic order', () {
      final trie = Trie.fromLines(['car', 'card', 'care', 'cat', 'dog']);

      expect(
        trie.withPrefix('ca'),
        containsAll(['car', 'card', 'care', 'cat']),
      );
      expect(trie.withPrefix('ca'), equals(['car', 'card', 'care', 'cat']));
      expect(trie.withPrefix('car', limit: 2), hasLength(2));
      expect(trie.withPrefix('xyz'), isEmpty);
    });

    test('fromLines normalizes case and ignores empty entries', () {
      final trie = Trie.fromLines(['Hello', '', '   ', 'world']);

      expect(trie.contains('hello'), isTrue);
      // insert() itself is case-sensitive; normalization lives in fromLines.
      expect(trie.contains('Hello'), isFalse);
      expect(trie.size, 2);
    });

    test('fromDictionary uses the dictionary terms', () {
      final dict = Dictionary.fromLines(['hello,5', 'world,2']);
      final trie = Trie.fromDictionary(dict);

      expect(trie.contains('hello'), isTrue);
      expect(trie.contains('world'), isTrue);
      expect(trie.size, 2);
    });

    test('handles unicode words', () {
      final trie = Trie.fromLines(['mamá', 'papá', 'mamífero']);

      expect(trie.contains('mamá'), isTrue);
      expect(trie.withPrefix('mam'), containsAll(['mamá', 'mamífero']));
    });
  });

  group('SymSpellEx.hasTerm', () {
    test('distinguishes terms from delete keys', () {
      final symSpell = SymSpellEx(MemoryStore())..initialize();
      symSpell.add('albert', 5);

      expect(symSpell.hasTerm('albert'), isTrue);
      expect(symSpell.hasTerm('Albert'), isTrue); // case-insensitive
      // 'albrt' is a delete key of 'albert', but not a dictionary term.
      expect(symSpell.hasTerm('albrt'), isFalse);
      expect(symSpell.hasTerm('unknown'), isFalse);
    });

    test('is language aware', () {
      final symSpell = SymSpellEx(MemoryStore())..initialize();
      symSpell.add('ممتاز', 1, Languages.arabic);

      expect(symSpell.hasTerm('ممتاز', Languages.arabic), isTrue);
      expect(symSpell.hasTerm('ممتاز', Languages.english), isFalse);
    });

    test('works with trainDictionary', () {
      final symSpell = SymSpellEx(MemoryStore())..initialize();
      symSpell.trainDictionary(Dictionary.fromLines(['hello,5', 'world,2']));

      expect(symSpell.hasTerm('hello'), isTrue);
      expect(symSpell.hasTerm('hllo'), isFalse);
    });
  });
}
