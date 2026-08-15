import 'dart:math' as math;

import '../../edit_distance.dart';

/// Fast Damerau-Levenshtein distance implementation.
///
/// Ported from `symspell-ex` (https://github.com/m-elbably/symspell-ex),
/// which is an optimization of David Hamp-Gonsalves' port of
/// https://github.com/microsoft/damlev.
class DamerauLevenshteinDistance implements EditDistance {
  @override
  final String name = 'DamerauLevenshtein';

  // Cache the codes and score arrays to significantly speed up damlev calls:
  // there's no need to re-allocate them.
  List<int> _sourceCodes = List<int>.filled(32, 0);
  List<int> _targetCodes = List<int>.filled(32, 0);
  List<int> _score = List<int>.filled(33 * 33, 0);

  /// Returns an array that's at least as large as the provided [size].
  List<int> _growArray(List<int> arr, int size) {
    if (size <= arr.length) {
      return arr;
    }

    var target = arr.length;
    while (target < size) {
      target *= 2;
    }

    return List<int>.filled(target, 0);
  }

  /// Returns the edit distance between the [source] and [target] strings.
  @override
  int calculateDistance(String source, String target) {
    // If one of the strings is blank, returns the length of the other (the
    // cost of the n insertions).
    if (source.isEmpty) {
      return target.length;
    } else if (target.isEmpty) {
      return source.length;
    }

    final sourceLength = source.length;
    final targetLength = target.length;
    var i = 0;

    // Initialize a char code cache array.
    _sourceCodes = _growArray(_sourceCodes, sourceLength);
    _targetCodes = _growArray(_targetCodes, targetLength);
    for (i = 0; i < sourceLength; i++) {
      _sourceCodes[i] = source.codeUnitAt(i);
    }
    for (i = 0; i < targetLength; i++) {
      _targetCodes[i] = target.codeUnitAt(i);
    }

    // Initialize the scoring matrix.
    final inf = sourceLength + targetLength;
    final rowSize = sourceLength + 1;
    _score = _growArray(_score, (sourceLength + 1) * (targetLength + 1));
    _score[0] = inf;

    for (i = 0; i <= sourceLength; i++) {
      _score[(i + 1) * rowSize] = inf;
      _score[(i + 1) * rowSize + 1] = i;
    }

    for (i = 0; i <= targetLength; i++) {
      _score[i] = inf;
      _score[1 * rowSize + i + 1] = i;
    }

    // Run the damlev algorithm.
    final chars = <int, int>{};
    var j = 0;
    var db = 0;
    var i1 = 0;
    var j1 = 0;
    var newScore = 0;
    for (i = 1; i <= sourceLength; i++) {
      db = 0;
      for (j = 1; j <= targetLength; j++) {
        i1 = chars[_targetCodes[j - 1]] ?? 0;
        j1 = db;

        if (_sourceCodes[i - 1] == _targetCodes[j - 1]) {
          newScore = _score[i * rowSize + j];
          db = j;
        } else {
          newScore =
              math.min(
                _score[i * rowSize + j],
                math.min(
                  _score[(i + 1) * rowSize + j],
                  _score[i * rowSize + j + 1],
                ),
              ) +
              1;
        }

        _score[(i + 1) * rowSize + j + 1] = math.min(
          newScore,
          _score[i1 * rowSize + j1] + (i - i1) + (j - j1 - 1),
        );
      }
      chars[_sourceCodes[i - 1]] = i;
    }

    return _score[(sourceLength + 1) * rowSize + targetLength + 1];
  }
}
