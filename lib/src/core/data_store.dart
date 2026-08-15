/// Backing store used by [SymSpellEx] to persist dictionary terms and
/// delete-key entries.
///
/// The API is synchronous because the default implementation is in-memory,
/// which keeps the per-keystroke lookup hot path allocation-free.
abstract class DataStore {
  String get name;

  void initialize();
  bool isInitialized();
  void setLanguage(String language);

  /// List data structure: stores terms by index.
  /// Returns the new length of the term list (matching `List.push` semantics).
  int pushTerm(String value);
  String? getTermAt(int index);
  List<String?> getTermsAt(List<int> indexes);

  /// Number of terms stored for the current language.
  int get termCount;

  /// Hash table data structure: stores entries by key.
  List<int>? getEntry(String key);
  List<List<int>?> getEntries(List<String> keys);
  bool setEntry(String key, List<int> value);
  bool hasEntry(String key);

  int maxEntryLength();
  void clear();
}
