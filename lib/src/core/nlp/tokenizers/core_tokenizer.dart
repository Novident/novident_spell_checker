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

  List<Token> _tokenizeSegment(String input, int baseOffset) {
    var tokens = <Token>[];
    for (final expression in _expressions) {
      final matches = expression.value.allMatches(input).toList();
      if (matches.isEmpty) {
        continue;
      }

      tokens = [];
      var cursor = 0;
      for (final match in matches) {
        // Untagged segment between the previous match and this one.
        if (match.start > cursor) {
          final part = input.substring(cursor, match.start);
          if (part.trim().isNotEmpty) {
            _tokenizeInput(Token(part), tokens, baseOffset + cursor);
          }
          // Whitespace-only segments are re-attached as the previous
          // token's exact spacing in tokenize().
        }

        final mToken = match.group(0)!;
        if (mToken.isNotEmpty) {
          tokens.add(Token(
            mToken,
            expression.tag,
            expression.alphabet,
            0,
            baseOffset + match.start,
          ));
        }
        cursor = match.end;
      }

      // Trailing untagged segment.
      if (cursor < input.length) {
        final part = input.substring(cursor);
        if (part.trim().isNotEmpty) {
          _tokenizeInput(Token(part), tokens, baseOffset + cursor);
        }
      }
      break; // The first matching expression defines the token split.
    }

    if (tokens.isEmpty) {
      // No expression matched: opaque token (keep the raw text).
      tokens.add(Token(input, TokenTags.none, null, 0, baseOffset));
    }

    return tokens;
  }

  void _tokenizeInput(Token input, List<Token> tokens, int baseOffset) {
    final tokenValue = input.value;
    if (tokenValue.trim().isEmpty) {
      return;
    }
    tokens.addAll(_tokenizeSegment(tokenValue, baseOffset));
  }

  @override
  List<Token> tokenize(String input) {
    if (input.isEmpty) {
      return [];
    }

    final tokens = _tokenizeSegment(input, 0);

    // Fold interior space tokens into the previous token's exact spacing
    // (they only appear when the space expression wins the cascade, e.g.
    // after opaque segments); leading whitespace stays as a token.
    final result = <Token>[];
    for (final token in tokens) {
      if (token.tag == TokenTags.space && result.isNotEmpty) {
        continue; // Re-attached below as the previous token's spacing.
      }
      result.add(token);
    }

    // Preserve leading whitespace for a lossless round-trip.
    if (result.isNotEmpty && result.first.offset > 0) {
      result.insert(
        0,
        Token(
          input.substring(0, result.first.offset),
          TokenTags.space,
          null,
          0,
          0,
        ),
      );
    }

    // Attach the exact trailing whitespace to each token.
    for (var i = 0; i < result.length; i++) {
      final token = result[i];
      final end = token.offset + token.value.length;
      final next = i + 1 < result.length ? result[i + 1].offset : input.length;
      token.spacing = input.substring(end, next);
      token.distance = token.spacing.isEmpty ? 0 : 1;
    }

    return result;
  }
}
