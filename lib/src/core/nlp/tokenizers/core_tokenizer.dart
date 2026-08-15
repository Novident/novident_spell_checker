import '../../constants.dart';
import '../../tokenizer.dart';
import '../../types.dart';

class _TokenExpression {
  final RegExp value;
  final String? tag;
  final String? alphabet;

  const _TokenExpression(this.value, this.tag, [this.alphabet]);
}

/// Default tokenizer ported from `symspell-ex`.
///
/// Classifies input into url / number / word / punctuation / space tokens for
/// both latin and arabic alphabets.
class CoreTokenizer implements Tokenizer {
  final List<_TokenExpression> _expressions = [
    _TokenExpression(
      RegExp(
        r'[(http(s)?)://(www\.)?a-zA-Z0-9@:%._\+~#=]{2,256}\.[a-z]{2,6}\b([-a-zA-Z0-9@:%_\+.~#?&//=]*)',
        caseSensitive: false,
      ),
      TokenTags.url,
    ),
    _TokenExpression(
      RegExp(r'\d+/\d+|\d(?:[.,-/]?\d)*(?:\.\d+)?'),
      TokenTags.number,
      Alphabets.latin,
    ),
    _TokenExpression(
      RegExp(r'[\u0660-\u0669]+'),
      TokenTags.number,
      Alphabets.arabic,
    ),
    _TokenExpression(
      RegExp(r'[A-zÀ-ú]+', caseSensitive: false),
      TokenTags.word,
      Alphabets.latin,
    ),
    _TokenExpression(
      RegExp(r'[\u0620-\u06EF]+'),
      TokenTags.word,
      Alphabets.arabic,
    ),
    _TokenExpression(
      RegExp(r'[.!?;\-()\[\]{}"]'),
      TokenTags.punctuation,
      Alphabets.latin,
    ),
    _TokenExpression(RegExp(r'[،؟]'), TokenTags.punctuation, Alphabets.arabic),
    _TokenExpression(RegExp(r'\s+'), TokenTags.space),
  ];

  List<Token> _tokenizeSegment(String input) {
    var tokens = <Token>[];
    for (final expression in _expressions) {
      final matches = expression.value
          .allMatches(input)
          .map((m) => m.group(0)!)
          .toList();
      final parts = input.split(expression.value);

      var mIndex = 0;
      tokens = [];
      for (var j = 0; j < parts.length; j++) {
        final part = parts[j];
        if (part.trim().isNotEmpty) {
          tokens.add(Token(part));
        }

        if (mIndex < matches.length) {
          final mToken = matches[mIndex].trim();
          if (mToken.isNotEmpty) {
            tokens.add(Token(mToken, expression.tag, expression.alphabet));
          }

          if (mToken.length >= input.length) {
            break;
          }
        }

        mIndex++;
      }

      if (matches.isNotEmpty) {
        break;
      }
    }

    if (tokens.length == 1 && tokens[0].tag == null) {
      tokens[0].tag = TokenTags.none;
    }

    return tokens;
  }

  void _tokenizeInput(Token input, List<Token> tokens) {
    final tokenValue = input.value.trim();
    if (tokenValue.isEmpty) {
      return;
    }

    final bTokens = _tokenizeSegment(tokenValue);
    for (var i = 0; i < bTokens.length; i++) {
      final pSpaceIndex = input.value.indexOf('${bTokens[i].value.trim()} ');
      final tDistance = pSpaceIndex >= 0 ? 1 : 0;
      bTokens[i].distance = i >= bTokens.length - 1
          ? input.distance
          : tDistance;

      if (bTokens[i].tag == null) {
        _tokenizeInput(bTokens[i], tokens);
      } else {
        tokens.add(bTokens[i]);
      }
    }
  }

  @override
  List<Token> tokenize(String input) {
    if (input.isEmpty) {
      return [];
    }

    final tokens = <Token>[];
    _tokenizeInput(Token(input), tokens);
    return tokens;
  }
}
