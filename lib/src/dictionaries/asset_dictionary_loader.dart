import 'package:flutter/services.dart';

import 'dictionary.dart';
import 'hunspell_dictionary.dart';

/// Loads a [Dictionary] from a Flutter asset bundle.
///
/// Register the dictionary file under `assets` in `pubspec.yaml`, e.g.:
///
/// ```yaml
/// flutter:
///   assets:
///     - assets/dictionaries/en-80k.txt
/// ```
class AssetDictionaryLoader {
  AssetDictionaryLoader._();

  /// Loads and parses the dictionary at [assetPath].
  ///
  /// [bundle] defaults to [rootBundle]; tests may inject a custom bundle.
  static Future<Dictionary> load(
    String assetPath, {
    AssetBundle? bundle,
  }) async {
    final data = await (bundle ?? rootBundle).loadString(assetPath);
    return Dictionary.fromLines(data.split('\n'));
  }

  /// Loads and parses a Hunspell `.dic` / personal dictionary asset
  /// (LibreOffice/Firefox/Chrome dictionary format) at [assetPath].
  static Future<HunspellDictionary> loadHunspell(
    String assetPath, {
    AssetBundle? bundle,
  }) async {
    final data = await (bundle ?? rootBundle).loadString(assetPath);
    return HunspellDictionary.fromString(data);
  }
}
