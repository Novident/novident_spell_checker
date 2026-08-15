import 'dictionary.dart';

/// A compact, memory-conscious trie for exact word membership and prefix
/// queries.
///
/// This solves the "is this word valid?" problem, not the "what should this
/// typo be?" problem — for fuzzy suggestions use [SymSpellEx]'s symmetric
/// delete index (which is the memory-heavy part of the library).
///
/// ## Why packed child/sibling arrays?
///
/// A naive node-per-character trie where every node owns a `Map` of children
/// loses to a plain `Set<String>` on memory in Dart because of per-object
/// overhead. This implementation stores the whole tree in four parallel
/// `List<int>`s (character, first child, next sibling, terminal flag), so a
/// node costs four machine ints and no object headers.
///
/// ## What a trie buys you over a `Set`
///
///  * Prefix queries ([withPrefix]) — autocomplete.
///  * Ordered iteration without sorting.
///  * Worst-case O(word length) membership without hashing.
///
/// For pure membership checks, `Set<String>` or [SymSpellEx.hasTerm] are
/// usually the better picks.
class Trie {
  final List<int> _char = [0]; // node 0 = root, char unused
  final List<int> _child = [-1];
  final List<int> _sibling = [-1];
  final List<int> _terminal = [0];
  int _size = 0;

  /// Number of distinct words stored.
  int get size => _size;

  /// Total number of nodes (root included). Useful as a memory proxy.
  int get nodeCount => _char.length;

  Trie();

  /// Builds a trie from plain words.
  ///
  /// Words are trimmed, lowercased and empty entries are ignored. Use
  /// [insert] directly if you need case-sensitive storage.
  factory Trie.fromLines(Iterable<String> words) {
    final trie = Trie();
    trie.addAll(words);
    return trie;
  }

  /// Builds a trie from the terms of a [Dictionary].
  factory Trie.fromDictionary(Dictionary dictionary) =>
      Trie.fromLines(dictionary.terms.keys);

  /// Adds [words] (trimmed, lowercased, empty entries ignored).
  void addAll(Iterable<String> words) {
    for (final word in words) {
      final trimmed = word.trim().toLowerCase();
      if (trimmed.isEmpty) {
        continue;
      }
      insert(trimmed);
    }
  }

  /// Inserts [word] exactly as given (no normalization).
  void insert(String word) {
    if (word.isEmpty) {
      return;
    }

    var node = 0;
    for (var i = 0; i < word.length; i++) {
      final code = word.codeUnitAt(i);

      var child = _child[node];
      var prev = -1;
      var found = -1;
      while (child != -1) {
        if (_char[child] == code) {
          found = child;
          break;
        }
        prev = child;
        child = _sibling[child];
      }

      if (found != -1) {
        node = found;
      } else {
        final created = _newNode(code);
        if (prev == -1) {
          _child[node] = created;
        } else {
          _sibling[prev] = created;
        }
        node = created;
      }
    }

    if (_terminal[node] == 0) {
      _terminal[node] = 1;
      _size++;
    }
  }

  /// Whether [word] is stored exactly as given (case-sensitive).
  bool contains(String word) {
    if (word.isEmpty) {
      return false;
    }

    var node = 0;
    for (var i = 0; i < word.length; i++) {
      node = _findChild(node, word.codeUnitAt(i));
      if (node == -1) {
        return false;
      }
    }
    return _terminal[node] == 1;
  }

  /// All stored words starting with [prefix], in lexicographic order,
  /// capped at [limit] results.
  List<String> withPrefix(String prefix, {int limit = 100}) {
    final results = <String>[];
    if (limit <= 0) {
      return results;
    }

    var node = 0;
    for (var i = 0; i < prefix.length; i++) {
      node = _findChild(node, prefix.codeUnitAt(i));
      if (node == -1) {
        return results;
      }
    }

    _collect(node, List<int>.of(prefix.codeUnits), results, limit);
    return results;
  }

  int _findChild(int node, int code) {
    var child = _child[node];
    while (child != -1) {
      if (_char[child] == code) {
        return child;
      }
      child = _sibling[child];
    }
    return -1;
  }

  int _newNode(int code) {
    _char.add(code);
    _child.add(-1);
    _sibling.add(-1);
    _terminal.add(0);
    return _char.length - 1;
  }

  void _collect(int node, List<int> path, List<String> out, int limit) {
    if (out.length >= limit) {
      return;
    }
    if (_terminal[node] == 1) {
      out.add(String.fromCharCodes(path));
      if (out.length >= limit) {
        return;
      }
    }

    var child = _child[node];
    while (child != -1 && out.length < limit) {
      path.add(_char[child]);
      _collect(child, path, out, limit);
      path.removeLast();
      child = _sibling[child];
    }
  }
}
