import 'dart:convert';
import 'dart:typed_data';

/// A parsed frequency dictionary: maps each term to its frequency.
///
/// Dictionaries are plain, language-agnostic data — the language is chosen
/// when the dictionary is applied to a [SymSpellEx] via `trainDictionary`.
///
/// Supported input formats (per line):
///
///  * `term,frequency` — symspell-ex `train` format.
///  * `term frequency` — Wolf Garbe frequency dictionaries
///    (e.g. `frequency_dictionary_en_82_765.txt`).
///  * `term` — plain word lists (frequency defaults to 1).
class Dictionary {
  /// Terms mapped to their frequencies.
  final Map<String, int> terms;

  Dictionary(Map<String, int> terms) : terms = Map.of(terms);

  /// Number of terms in this dictionary.
  int get length => terms.length;

  /// Whether this dictionary contains no terms.
  bool get isEmpty => terms.isEmpty;

  /// Parses [lines] into a [Dictionary].
  ///
  /// Empty lines and lines starting with `#` are ignored. Records whose
  /// frequency cannot be parsed as an integer are skipped.
  factory Dictionary.fromLines(List<String> lines) {
    final terms = <String, int>{};
    for (final line in lines) {
      _addLine(line, terms);
    }
    return Dictionary(terms);
  }

  /// Parses a stream of lines without holding the raw content in memory —
  /// suitable for very large dictionaries read incrementally.
  ///
  /// Use together with [fromByteStream] or build the line stream yourself
  /// (e.g. `file.openRead().transform(utf8.decoder)
  /// .transform(const LineSplitter())`).
  static Future<Dictionary> fromLineStream(Stream<String> lines) async {
    final terms = <String, int>{};
    await for (final line in lines) {
      _addLine(line, terms);
    }
    return Dictionary(terms);
  }

  /// Parses raw UTF-8 byte chunks (e.g. `File.openRead()` output).
  ///
  /// Multi-byte characters split across chunk boundaries and lines split
  /// across chunks are handled correctly, so the caller may read with any
  /// chunk size.
  static Future<Dictionary> fromByteStream(Stream<List<int>> bytes) {
    return fromLineStream(
      bytes.transform(utf8.decoder).transform(const LineSplitter()),
    );
  }

  static void _addLine(String rawLine, Map<String, int> terms) {
    final line = rawLine.replaceFirst('\uFEFF', '').trim();
    if (line.isEmpty || line.startsWith('#')) {
      return;
    }

    final parts = line.split(RegExp(r'[,\s]+'));
    if (parts.isEmpty || parts[0].isEmpty) {
      return;
    }

    if (parts.length == 1) {
      // Plain word list.
      terms[parts[0]] = 1;
      return;
    }

    final frequency = int.tryParse(parts[1]);
    if (frequency == null) {
      return;
    }
    terms[parts[0]] = frequency;
  }

  /// Parses a single [csv] string with newline-separated records.
  factory Dictionary.fromCsv(String csv) =>
      Dictionary.fromLines(csv.split('\n'));

  /// Parses raw UTF-8 [bytes] (a dictionary file read with
  /// `File(...).readAsBytes()`).
  factory Dictionary.fromBytes(Uint8List bytes) =>
      Dictionary.fromLines(utf8.decode(bytes).split('\n'));

  /// Wraps an existing term-to-frequency [terms] map.
  factory Dictionary.fromMap(Map<String, int> terms) => Dictionary(terms);

  /// Serializes back to symspell-ex compatible records
  /// (`term,frequency`), most frequent first.
  List<String> toLines() {
    final entries = terms.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.map((e) => '${e.key},${e.value}').toList(growable: false);
  }

  /// Encodes the dictionary as UTF-8 bytes in its file format
  /// (`term,frequency` per line), ready for
  /// `File('...').writeAsBytes(dict.toBytes())`. Round-trips with
  /// [Dictionary.fromBytes].
  Uint8List toBytes() {
    final buffer = StringBuffer();
    for (final line in toLines()) {
      buffer
        ..write(line)
        ..write('\n');
    }
    return Uint8List.fromList(utf8.encode(buffer.toString()));
  }

  /// Streams the dictionary as UTF-8 byte chunks (lines batched ~512 per
  /// chunk) — for writing incrementally without building the full byte
  /// buffer:
  ///
  /// ```dart
  /// await dict.toByteStream().pipe(File('dict.txt').openWrite());
  /// ```
  Stream<List<int>> toByteStream() async* {
    const batchSize = 512;
    var buffer = StringBuffer();
    var count = 0;
    for (final line in toLines()) {
      buffer
        ..write(line)
        ..write('\n');
      count++;
      if (count >= batchSize) {
        yield Uint8List.fromList(utf8.encode(buffer.toString()));
        buffer = StringBuffer();
        count = 0;
      }
    }
    if (count > 0) {
      yield Uint8List.fromList(utf8.encode(buffer.toString()));
    }
  }
}
