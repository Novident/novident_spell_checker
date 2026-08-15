import 'dart:convert';
import 'dart:typed_data';

/// Parsed Hunspell affix rules (`.aff`).
///
/// Supports the directives that matter for form generation:
/// `SET` (ignored — input is always UTF-8), `FLAG` (default single-char,
/// `long`, `num`, `UTF-8`), `PFX` and `SFX` (header + rule lines, including
/// stripping, conditions, cross products and `/` continuation classes).
/// Everything else (`TRY`, `REP`, `KEY`, `ICONV`, compounding, …) is
/// ignored: those affect suggestion ranking and compound checking, not the
/// set of valid word forms.
///
/// Usage (optional — dictionaries work without it, better with it):
///
/// ```dart
/// final affix = AffixRules.fromString(affContent);
/// final fullForms = hunspellDict.expand(affix); // Dictionary
/// speller.trainDictionary(fullForms, language);
/// ```
class AffixRules {
  AffixRules._(this._flagType, this._prefixes, this._suffixes);

  final _FlagType _flagType;
  final Map<String, _AffixClass> _prefixes;
  final Map<String, _AffixClass> _suffixes;

  static const int _maxDepth = 10;

  /// Parses [lines] into [AffixRules].
  factory AffixRules.fromLines(List<String> lines) {
    final parser = _AffixParser();
    for (final line in lines) {
      parser.addLine(line);
    }
    return parser.build();
  }

  /// Parses a single [data] string with newline-separated records.
  factory AffixRules.fromString(String data) =>
      AffixRules.fromLines(data.split('\n'));

  /// Parses raw UTF-8 [bytes] (an `.aff` file read with
  /// `File(...).readAsBytes()`).
  factory AffixRules.fromBytes(Uint8List bytes) =>
      AffixRules.fromString(utf8.decode(bytes));

  /// Parses a stream of lines without holding the raw content in memory.
  static Future<AffixRules> fromLineStream(Stream<String> lines) async {
    final parser = _AffixParser();
    await for (final line in lines) {
      parser.addLine(line);
    }
    return parser.build();
  }

  /// Parses raw UTF-8 byte chunks (chunk-boundary-safe).
  static Future<AffixRules> fromByteStream(Stream<List<int>> bytes) {
    return fromLineStream(
      bytes.transform(utf8.decoder).transform(const LineSplitter()),
    );
  }

  /// Splits a raw flag string (as stored in a `.dic` entry) according to
  /// the declared `FLAG` type.
  List<String> splitFlags(String flagPart) {
    switch (_flagType) {
      case _FlagType.long:
        final flags = <String>[];
        for (var i = 0; i + 1 < flagPart.length; i += 2) {
          flags.add(flagPart.substring(i, i + 2));
        }
        if (flagPart.length.isOdd) {
          flags.add(flagPart.substring(flagPart.length - 1));
        }
        return flags;
      case _FlagType.num:
        return flagPart
            .split(',')
            .where((f) => f.isNotEmpty)
            .toList(growable: false);
      case _FlagType.utf8:
        return flagPart.runes
            .map((r) => String.fromCharCode(r))
            .toList(growable: false);
      case _FlagType.single:
        return flagPart.split('');
    }
  }

  /// Generates all valid forms of [word] under [flagPart], including
  /// [word] itself.
  ///
  /// Prefix rules, suffix rules, cross products (when both classes allow
  /// them) and continuation classes are applied, with cycle and depth
  /// guards. Conditions are matched against the start of the word for
  /// prefixes and the end of the word for suffixes.
  Set<String> expand(String word, String flagPart) {
    final result = <String>{word};
    final flags = splitFlags(flagPart);
    if (flags.isEmpty) {
      return result;
    }
    _expandForms(word, flags, result, <String>{}, 0);
    return result;
  }

  void _expandForms(
    String word,
    List<String> flags,
    Set<String> out,
    Set<String> visited,
    int depth,
  ) {
    if (depth >= _maxDepth) {
      return;
    }

    final prefixed = <(String, _AffixClass)>[];
    for (final flag in flags) {
      final cls = _prefixes[flag];
      if (cls == null) {
        continue;
      }
      final key = '$word|P$flag';
      if (!visited.add(key)) {
        continue;
      }
      for (final rule in cls.rules) {
        final form = _applyPrefix(word, rule);
        if (form == null || form.isEmpty || form == word) {
          continue;
        }
        out.add(form);
        prefixed.add((form, cls));
        final continuation = rule.continuation;
        if (continuation != null) {
          _expandForms(form, splitFlags(continuation), out, visited, depth + 1);
        }
      }
    }

    final suffixed = <(String, _AffixClass)>[];
    for (final flag in flags) {
      final cls = _suffixes[flag];
      if (cls == null) {
        continue;
      }
      final key = '$word|S$flag';
      if (!visited.add(key)) {
        continue;
      }
      for (final rule in cls.rules) {
        final form = _applySuffix(word, rule);
        if (form == null || form.isEmpty || form == word) {
          continue;
        }
        out.add(form);
        suffixed.add((form, cls));
        final continuation = rule.continuation;
        if (continuation != null) {
          _expandForms(form, splitFlags(continuation), out, visited, depth + 1);
        }
      }
    }

    // Cross products: a prefixed form combined with a suffix class.
    // Both the prefix class and the suffix class must allow crossing.
    for (final (prefixForm, prefixClass) in prefixed) {
      if (!prefixClass.crossProduct) {
        continue;
      }
      for (final flag in flags) {
        final suffixClass = _suffixes[flag];
        if (suffixClass == null || !suffixClass.crossProduct) {
          continue;
        }
        for (final rule in suffixClass.rules) {
          final form = _applySuffix(prefixForm, rule);
          if (form == null || form.isEmpty) {
            continue;
          }
          out.add(form);
          final continuation = rule.continuation;
          if (continuation != null) {
            _expandForms(
                form, splitFlags(continuation), out, visited, depth + 1);
          }
        }
      }
    }
  }

  String? _applyPrefix(String word, _AffixRule rule) {
    if (!rule.matches(word, isPrefix: true)) {
      return null;
    }
    if (rule.strip != '0' && !word.startsWith(rule.strip)) {
      return null;
    }
    final stem = rule.strip == '0' ? word : word.substring(rule.strip.length);
    if (rule.add == '0') {
      return stem;
    }
    return rule.add + stem;
  }

  String? _applySuffix(String word, _AffixRule rule) {
    if (!rule.matches(word, isPrefix: false)) {
      return null;
    }
    if (rule.strip != '0' && !word.endsWith(rule.strip)) {
      return null;
    }
    final stem = rule.strip == '0'
        ? word
        : word.substring(0, word.length - rule.strip.length);
    if (rule.add == '0') {
      return stem;
    }
    return stem + rule.add;
  }
}

enum _FlagType { single, long, num, utf8 }

class _AffixClass {
  _AffixClass(this.flag, this.crossProduct);

  final String flag;
  final bool crossProduct;
  final List<_AffixRule> rules = [];
}

/// A single affix rule with its condition pre-parsed into matchers.
class _AffixRule {
  _AffixRule(this.strip, String add, this.condition) {
    final slash = add.indexOf('/');
    if (slash == -1) {
      this.add = add;
    } else {
      this.add = add.substring(0, slash);
      continuation = add.substring(slash + 1);
    }
    matchers = _parseCondition(condition);
  }

  final String strip;
  late final String add;
  String? continuation;
  final String condition;
  late final List<_CharMatcher> matchers;

  /// Suffix conditions are matched against the word end, prefix conditions
  /// against the word start — in both cases left-to-right.
  bool matches(String word, {required bool isPrefix}) {
    if (word.length < matchers.length) {
      return false;
    }
    final offset = isPrefix ? 0 : word.length - matchers.length;
    for (var i = 0; i < matchers.length; i++) {
      if (!matchers[i].matches(word[offset + i])) {
        return false;
      }
    }
    return true;
  }

  static List<_CharMatcher> _parseCondition(String condition) {
    final matchers = <_CharMatcher>[];
    var i = 0;
    while (i < condition.length) {
      final c = condition[i];
      if (c == '.') {
        // Hunspell wildcard: matches any single character.
        matchers.add(_CharMatcher.any());
        i++;
      } else if (c == '[') {
        final end = condition.indexOf(']', i);
        if (end == -1) {
          matchers.add(_CharMatcher.single(c));
          i++;
        } else {
          final body = condition.substring(i + 1, end);
          final negated = body.startsWith('^');
          final chars = (negated ? body.substring(1) : body).split('').toSet();
          matchers.add(_CharMatcher.setOf(chars, negated: negated));
          i = end + 1;
        }
      } else {
        matchers.add(_CharMatcher.single(c));
        i++;
      }
    }
    return matchers;
  }
}

class _CharMatcher {
  _CharMatcher.single(this.char)
      : chars = null,
        negated = false,
        any = false;

  _CharMatcher.setOf(this.chars, {required this.negated})
      : char = null,
        any = false;
  _CharMatcher.any()
      : char = null,
        chars = null,
        negated = false,
        any = true;

  final String? char;
  final Set<String>? chars;
  final bool negated;
  final bool any;

  bool matches(String c) {
    if (any) {
      return true;
    }
    if (char != null) {
      return c == char;
    }
    final inSet = chars!.contains(c);
    return negated ? !inSet : inSet;
  }
}

/// Incremental line parser shared by [AffixRules.fromLines] and
/// [AffixRules.fromLineStream].
class _AffixParser {
  _FlagType _flagType = _FlagType.single;
  final Map<String, _AffixClass> prefixes = {};
  final Map<String, _AffixClass> suffixes = {};

  void addLine(String rawLine) {
    final line = rawLine.replaceFirst('\uFEFF', '').trim();
    if (line.isEmpty || line.startsWith('#')) {
      return;
    }

    final tokens = line.split(RegExp(r'\s+'));
    switch (tokens[0]) {
      case 'FLAG':
        if (tokens.length >= 2) {
          _flagType = switch (tokens[1]) {
            'long' => _FlagType.long,
            'num' => _FlagType.num,
            'UTF-8' => _FlagType.utf8,
            _ => _FlagType.single,
          };
        }
        return;
      case 'PFX':
        if (tokens.length == 4) {
          prefixes[tokens[1]] = _AffixClass(tokens[1], tokens[2] == 'Y');
        } else if (tokens.length >= 5) {
          prefixes[tokens[1]]?.rules.add(
                _AffixRule(tokens[2], tokens[3], tokens[4]),
              );
        }
        return;
      case 'SFX':
        if (tokens.length == 4) {
          suffixes[tokens[1]] = _AffixClass(tokens[1], tokens[2] == 'Y');
        } else if (tokens.length >= 5) {
          suffixes[tokens[1]]?.rules.add(
                _AffixRule(tokens[2], tokens[3], tokens[4]),
              );
        }
        return;
      default:
        return; // SET, TRY, REP, KEY, ICONV, compounding, … — ignored.
    }
  }

  AffixRules build() => AffixRules._(_flagType, prefixes, suffixes);
}
