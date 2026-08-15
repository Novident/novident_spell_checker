import 'types.dart';

/// Splits an input string into typed [Token]s.
abstract class Tokenizer {
  List<Token> tokenize(String input);
}
