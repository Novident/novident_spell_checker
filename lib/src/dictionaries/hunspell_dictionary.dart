import 'dart:convert';
import 'dart:typed_data';

import 'dictionary.dart';

/// A parsed Hunspell dictionary (`.dic`) and/or personal dictionary.
///
/// Hunspell dictionary files are plain text: one word per line, optionally
/// followed by `/FLAGS`. This means an ordinary word list (one word per
/// line) is already a valid Hunspell dictionary — this parser bridges the
/// LibreOffice dictionary ecosystem (dictionaries shipped with LibreOffice,
/// Firefox, Chrome, macOS) into this library's structures.
///
/// Handles:
///  * the optional word-count header on the first line of a main `.dic`,
///  * `word/FLAGS` entries (flags are preserved in [flags] for a future
///    affix-expansion build step, and stripped from the term),
///  * escaped slashes inside words (`and\/or`),
///  * personal dictionary entries: forbidden words (`*word`) and
///    multi-word pairs (`a lot`, used for missing-space corrections),
///  * a UTF-8 BOM on the first line.
///
/// Note: flags are parsed but **not expanded**. Affix-heavy dictionaries
/// (e.g. `de_DE`) store only stems; to check inflected forms, use a
/// full-form dictionary variant (e.g. LibreOffice's `es_ANY.dic` for
/// Spanish) or implement `.aff` expansion as a separate build step.
class HunspellDictionary {
  /// Regular terms (flags stripped), frequency 1 each.
  final Dictionary terms;

  /// Forbidden words from personal dictionaries (`*word` entries),
  /// normalized to lowercase. These must never be trained; check them
  /// before accepting a word as valid.
  final Set<String> forbidden;

  /// Multi-word entries (e.g. `a lot`) used for missing-space suggestions.
  final List<String> pairs;

  /// Affix flags per term (e.g. `work` -> `AB`), for a future affix
  /// expansion step.
  final Map<String, String> flags;

  HunspellDictionary({
    Dictionary? terms,
    Set<String>? forbidden,
    List<String>? pairs,
    Map<String, String>? flags,
  }) : terms = terms ?? Dictionary(const {}),
       forbidden = forbidden ?? const <String>{},
       pairs = pairs ?? const <String>[],
       flags = flags ?? const <String, String>{};

  /// Number of regular terms.
  int get length => terms.length;

  /// Parses [lines] into a [HunspellDictionary].
  factory HunspellDictionary.fromLines(List<String> lines) {
    final parser = _HunspellParser();
    for (final line in lines) {
      parser.addLine(line);
    }
    return parser.build();
  }

  /// Parses a stream of lines without holding the raw content in memory —
  /// suitable for very large `.dic` files read incrementally.
  static Future<HunspellDictionary> fromLineStream(Stream<String> lines) async {
    final parser = _HunspellParser();
    await for (final line in lines) {
      parser.addLine(line);
    }
    return parser.build();
  }

  /// Parses raw UTF-8 byte chunks (e.g. `File.openRead()` output).
  /// Multi-byte characters and lines split across chunk boundaries are
  /// handled correctly, so the caller may read with any chunk size.
  static Future<HunspellDictionary> fromByteStream(Stream<List<int>> bytes) {
    return fromLineStream(
      bytes.transform(utf8.decoder).transform(const LineSplitter()),
    );
  }

  /// Parses a single [data] string with newline-separated records.
  factory HunspellDictionary.fromString(String data) =>
      HunspellDictionary.fromLines(data.split('\n'));

  /// Parses raw UTF-8 [bytes] (a `.dic` file read with
  /// `File(...).readAsBytes()`).
  factory HunspellDictionary.fromBytes(Uint8List bytes) =>
      HunspellDictionary.fromString(utf8.decode(bytes));

  /// Serializes back to Hunspell `.dic` format lines:
  ///
  ///  * `word` for terms without flags, `word/FLAGS` for flagged terms,
  ///    most frequent first,
  ///  * multi-word pairs (`a lot`),
  ///  * `*word` for forbidden entries.
  ///
  /// When [includeCountHeader] is true, the first line is the approximate
  /// entry count (main `.dic` convention; personal dictionaries have none).
  /// Re-parsing with [HunspellDictionary.fromLines] round-trips losslessly.
  ///
  /// Note: frequencies are dropped — the Hunspell format has no frequency
  /// field. Use [Dictionary.toLines] when frequencies must be preserved.
  List<String> toLines({bool includeCountHeader = false}) {
    final lines = <String>[];

    if (includeCountHeader) {
      lines.add('${terms.length + pairs.length}');
    }

    final sorted = terms.terms.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final entry in sorted) {
      final flag = flags[entry.key];
      lines.add(flag == null ? entry.key : '${entry.key}/$flag');
    }

    lines.addAll(pairs);
    for (final word in forbidden) {
      lines.add('*$word');
    }

    return lines;
  }

  /// [toLines] joined with newlines — ready to write to a file.
  String toText({bool includeCountHeader = false}) =>
      toLines(includeCountHeader: includeCountHeader).join('\n');

  /// Encodes the dictionary as UTF-8 bytes in Hunspell `.dic` format,
  /// ready for `File('...').writeAsBytes(dict.toBytes())`. Round-trips
  /// with [HunspellDictionary.fromBytes].
  Uint8List toBytes({bool includeCountHeader = false}) {
    final text = toText(includeCountHeader: includeCountHeader);
    final buffer = text.isEmpty ? '' : '$text\n';
    return Uint8List.fromList(utf8.encode(buffer));
  }

  /// Streams the dictionary as UTF-8 byte chunks (lines batched ~512 per
  /// chunk) — for writing incrementally without building the full byte
  /// buffer:
  ///
  /// ```dart
  /// await dict.toByteStream(includeCountHeader: true)
  ///     .pipe(File('dict.dic').openWrite());
  /// ```
  Stream<List<int>> toByteStream({bool includeCountHeader = false}) async* {
    const batchSize = 512;
    var buffer = StringBuffer();
    var count = 0;
    for (final line in toLines(includeCountHeader: includeCountHeader)) {
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

  static int _unescapedSlashIndex(String line) {
    for (var i = 0; i < line.length; i++) {
      if (line.codeUnitAt(i) == 0x2F /* / */ &&
          (i == 0 || line.codeUnitAt(i - 1) != 0x5C /* \ */ )) {
        return i;
      }
    }
    return -1;
  }
}

/// Incremental line parser shared by [HunspellDictionary.fromLines] and
/// [HunspellDictionary.fromLineStream].
class _HunspellParser {
  final termsMap = <String, int>{};
  final forbidden = <String>{};
  final pairs = <String>[];
  final flags = <String, String>{};
  bool _isFirstLine = true;

  void addLine(String rawLine) {
    var line = rawLine.replaceFirst('\uFEFF', '').trim();
    if (line.isEmpty) {
      return;
    }

    if (_isFirstLine) {
      _isFirstLine = false;
      // Optional word-count header of a main dictionary file.
      if (int.tryParse(line) != null) {
        return;
      }
    }

    // Personal dictionary: entries starting with '*' are forbidden words.
    if (line.startsWith('*')) {
      final word = line.substring(1).trim().toLowerCase();
      if (word.isNotEmpty) {
        forbidden.add(word);
      }
      return;
    }

    // Split the word from its flags at the first unescaped slash.
    final slashIndex = HunspellDictionary._unescapedSlashIndex(line);
    final wordPart = slashIndex == -1 ? line : line.substring(0, slashIndex);
    final flagPart = slashIndex == -1
        ? ''
        : line.substring(slashIndex + 1).trim();
    final word = wordPart.replaceAll(r'\/', '/').trim();

    if (word.isEmpty) {
      return;
    }

    // Multi-word entries ("a lot") fix common missing-space mistakes.
    if (word.contains(RegExp(r'\s'))) {
      pairs.add(word.replaceAll(RegExp(r'\s+'), ' '));
      return;
    }

    termsMap[word] = 1;
    if (flagPart.isNotEmpty) {
      // In personal dictionaries the part after '/' is an example word
      // for affix adoption, not flags; either way it's kept verbatim
      // and is irrelevant until affix expansion is implemented.
      flags[word] = flagPart;
    }
  }

  HunspellDictionary build() {
    return HunspellDictionary(
      terms: Dictionary(termsMap),
      forbidden: Set<String>.unmodifiable(forbidden),
      pairs: List<String>.unmodifiable(pairs),
      flags: Map<String, String>.unmodifiable(flags),
    );
  }
}
