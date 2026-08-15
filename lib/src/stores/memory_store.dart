import '../core/constants.dart';
import '../core/data_store.dart';

/// In-memory [DataStore] implementation, ported from `symspell-ex`.
class MemoryStore implements DataStore {
  @override
  final String name = 'memory_store';

  String _language = Languages.english;
  final Map<String, List<String>> _terms = {};
  final Map<String, Map<String, List<int>>> _entries = {};
  int _maxEntryLength = 0;
  bool _initialized = false;

  /// Number of terms stored for the current language.
  @override
  int get termCount => _terms[_language]?.length ?? 0;

  /// Number of hash entries (terms + delete keys) for the current language.
  /// Useful as a memory proxy for the symmetric delete index.
  int get entryCount => _entries[_language]?.length ?? 0;

  @override
  void initialize() {
    _terms.clear();
    _entries.clear();
    _terms[_language] = [];
    _entries[_language] = {};
    _initialized = true;
  }

  @override
  bool isInitialized() => _initialized;

  @override
  void setLanguage(String language) {
    _terms.putIfAbsent(language, () => []);
    _entries.putIfAbsent(language, () => {});
    _language = language;
  }

  @override
  int pushTerm(String key) {
    final terms = _terms[_language]!;
    terms.add(key);
    return terms.length;
  }

  @override
  String? getTermAt(int index) {
    final terms = _terms[_language]!;
    return index < terms.length ? terms[index] : null;
  }

  @override
  List<String?> getTermsAt(List<int> indexes) {
    final terms = _terms[_language]!;
    return indexes
        .map((i) => i < terms.length ? terms[i] : null)
        .toList(growable: false);
  }

  @override
  List<int>? getEntry(String key) {
    if (key.isEmpty) {
      return null;
    }
    return _entries[_language]![key];
  }

  @override
  List<List<int>?> getEntries(List<String> keys) {
    final entries = _entries[_language]!;
    return keys.map((k) => entries[k]).toList(growable: false);
  }

  @override
  bool setEntry(String key, List<int> value) {
    _entries[_language]![key] = value;

    if (key.length > _maxEntryLength) {
      _maxEntryLength = key.length;
    }
    return true;
  }

  @override
  bool hasEntry(String key) => _entries[_language]!.containsKey(key);

  @override
  int maxEntryLength() => _maxEntryLength;

  @override
  void clear() {
    _terms.clear();
    _entries.clear();
    _terms[_language] = [];
    _entries[_language] = {};
  }
}
