/// Token tags used by the tokenizer to classify input segments.
abstract final class TokenTags {
  static const String url = 'url';
  static const String number = 'number';
  static const String word = 'word';
  static const String punctuation = 'punctuation';
  static const String space = 'space';
  static const String none = 'none';
}

/// Supported alphabets.
abstract final class Alphabets {
  static const String latin = 'latin';
  static const String arabic = 'arabic';
}

/// Language codes (ISO 639-1 / IETF language tags).
///
/// Ported from `symspell-ex` (https://github.com/m-elbably/symspell-ex).
abstract final class Languages {
  static const String afrikaans = 'af';
  static const String albanian = 'sq';
  static const String aragonese = 'an';
  static const String arabic = 'ar';
  static const String arabicAlgeria = 'ar-dz';
  static const String arabicBahrain = 'ar-bh';
  static const String arabicEgypt = 'ar-eg';
  static const String arabicIraq = 'ar-iq';
  static const String arabicJordan = 'ar-jo';
  static const String arabicKuwait = 'ar-kw';
  static const String arabicLebanon = 'ar-lb';
  static const String arabicLibya = 'ar-ly';
  static const String arabicMorocco = 'ar-ma';
  static const String arabicOman = 'ar-om';
  static const String arabicQatar = 'ar-qa';
  static const String arabicSaudiArabia = 'ar-sa';
  static const String arabicSyria = 'ar-sy';
  static const String arabicTunisia = 'ar-tn';
  static const String arabicUae = 'ar-ae';
  static const String arabicYemen = 'ar-ye';
  static const String armenian = 'hy';
  static const String assamese = 'as';
  static const String asturian = 'ast';
  static const String azerbaijani = 'az';
  static const String basque = 'eu';
  static const String bulgarian = 'bg';
  static const String belarusian = 'be';
  static const String bengali = 'bn';
  static const String bosnian = 'bs';
  static const String breton = 'br';
  static const String burmese = 'my';
  static const String catalan = 'ca';
  static const String chamorro = 'ch';
  static const String chechen = 'ce';
  static const String chinese = 'zh';
  static const String chineseHongKong = 'zh-hk';
  static const String chinesePrc = 'zh-cn';
  static const String chineseSingapore = 'zh-sg';
  static const String chineseTaiwan = 'zh-tw';
  static const String chuvash = 'cv';
  static const String corsican = 'co';
  static const String cree = 'cr';
  static const String croatian = 'hr';
  static const String czech = 'cs';
  static const String danish = 'da';
  static const String dutchStandard = 'nl';
  static const String dutchBelgian = 'nl-be';
  static const String english = 'en';
  static const String englishAustralia = 'en-au';
  static const String englishBelize = 'en-bz';
  static const String englishCanada = 'en-ca';
  static const String englishIreland = 'en-ie';
  static const String englishJamaica = 'en-jm';
  static const String englishNewZealand = 'en-nz';
  static const String englishPhilippines = 'en-ph';
  static const String englishSouthAfrica = 'en-za';
  static const String englishTrinidadTobago = 'en-tt';
  static const String englishUk = 'en-gb';
  static const String englishUs = 'en-us';
  static const String englishZimbabwe = 'en-zw';
  static const String esperanto = 'eo';
  static const String estonian = 'et';
  static const String faeroese = 'fo';
  static const String farsi = 'fa';
  static const String fijian = 'fj';
  static const String finnish = 'fi';
  static const String frenchStandard = 'fr';
  static const String frenchBelgium = 'fr-be';
  static const String frenchCanada = 'fr-ca';
  static const String frenchFrance = 'fr-fr';
  static const String frenchLuxembourg = 'fr-lu';
  static const String frenchMonaco = 'fr-mc';
  static const String frenchSwitzerland = 'fr-ch';
  static const String frisian = 'fy';
  static const String friulian = 'fur';
  static const String gaelicScots = 'gd';
  static const String gaelicIrish = 'gd-ie';
  static const String galacian = 'gl';
  static const String georgian = 'ka';
  static const String germanStandard = 'de';
  static const String germanAustria = 'de-at';
  static const String germanGermany = 'de-de';
  static const String germanLiechtenstein = 'de-li';
  static const String germanLuxembourg = 'de-lu';
  static const String germanSwitzerland = 'de-ch';
  static const String greek = 'el';
  static const String gujurati = 'gu';
  static const String haitian = 'ht';
  static const String hebrew = 'he';
  static const String hindi = 'hi';
  static const String hungarian = 'hu';
  static const String icelandic = 'is';
  static const String indonesian = 'id';
  static const String inuktitut = 'iu';
  static const String irish = 'ga';
  static const String italianStandard = 'it';
  static const String italianSwitzerland = 'it-ch';
  static const String japanese = 'ja';
  static const String kannada = 'kn';
  static const String kashmiri = 'ks';
  static const String kazakh = 'kk';
  static const String khmer = 'km';
  static const String kirghiz = 'ky';
  static const String klingon = 'tlh';
  static const String korean = 'ko';
  static const String koreanNorthKorea = 'ko-kp';
  static const String koreanSouthKorea = 'ko-kr';
  static const String latin = 'la';
  static const String latvian = 'lv';
  static const String lithuanian = 'lt';
  static const String luxembourgish = 'lb';
  static const String fyroMacedonian = 'mk';
  static const String malay = 'ms';
  static const String malayalam = 'ml';
  static const String maltese = 'mt';
  static const String maori = 'mi';
  static const String marathi = 'mr';
  static const String moldavian = 'mo';
  static const String navajo = 'nv';
  static const String ndonga = 'ng';
  static const String nepali = 'ne';
  static const String norwegian = 'no';
  static const String norwegianBokmal = 'nb';
  static const String norwegianNynorsk = 'nn';
  static const String occitan = 'oc';
  static const String oriya = 'or';
  static const String oromo = 'om';
  static const String persian = 'fa';
  static const String persianIran = 'fa-ir';
  static const String polish = 'pl';
  static const String portuguese = 'pt';
  static const String portugueseBrazil = 'pt-br';
  static const String punjabi = 'pa';
  static const String punjabiIndia = 'pa-in';
  static const String punjabiPakistan = 'pa-pk';
  static const String quechua = 'qu';
  static const String rhaetoRomanic = 'rm';
  static const String romanian = 'ro';
  static const String romanianMoldavia = 'ro-mo';
  static const String russian = 'ru';
  static const String russianMoldavia = 'ru-mo';
  static const String samiLappish = 'sz';
  static const String sango = 'sg';
  static const String sanskrit = 'sa';
  static const String sardinian = 'sc';
  static const String scotsGaelic = 'gd';
  static const String sindhi = 'sd';
  static const String singhalese = 'si';
  static const String serbian = 'sr';
  static const String slovak = 'sk';
  static const String slovenian = 'sl';
  static const String somani = 'so';
  static const String sorbian = 'sb';
  static const String spanish = 'es';
  static const String spanishArgentina = 'es-ar';
  static const String spanishBolivia = 'es-bo';
  static const String spanishChile = 'es-cl';
  static const String spanishColombia = 'es-co';
  static const String spanishCostaRica = 'es-cr';
  static const String spanishDominicanRepublic = 'es-do';
  static const String spanishEcuador = 'es-ec';
  static const String spanishElSalvador = 'es-sv';
  static const String spanishGuatemala = 'es-gt';
  static const String spanishHonduras = 'es-hn';
  static const String spanishMexico = 'es-mx';
  static const String spanishNicaragua = 'es-ni';
  static const String spanishPanama = 'es-pa';
  static const String spanishParaguay = 'es-py';
  static const String spanishPeru = 'es-pe';
  static const String spanishPuertoRico = 'es-pr';
  static const String spanishSpain = 'es-es';
  static const String spanishUruguay = 'es-uy';
  static const String spanishVenezuela = 'es-ve';
  static const String sutu = 'sx';
  static const String swahili = 'sw';
  static const String swedish = 'sv';
  static const String swedishFinland = 'sv-fi';
  static const String swedishSweden = 'sv-sv';
  static const String tamil = 'ta';
  static const String tatar = 'tt';
  static const String teluga = 'te';
  static const String thai = 'th';
  static const String tigre = 'tig';
  static const String tsonga = 'ts';
  static const String tswana = 'tn';
  static const String turkish = 'tr';
  static const String turkmen = 'tk';
  static const String ukrainian = 'uk';
  static const String upperSorbian = 'hsb';
  static const String urdu = 'ur';
  static const String venda = 've';
  static const String vietnamese = 'vi';
  static const String volapuk = 'vo';
  static const String walloon = 'wa';
  static const String welsh = 'cy';
  static const String xhosa = 'xh';
  static const String yiddish = 'ji';
  static const String zulu = 'zu';
}

/// Maps a language code to its alphabet.
const Map<String, String> languagesAlphabet = {
  'ar': Alphabets.arabic,
  'ar-dz': Alphabets.arabic,
  'ar-bh': Alphabets.arabic,
  'ar-eg': Alphabets.arabic,
  'ar-iq': Alphabets.arabic,
  'ar-jo': Alphabets.arabic,
  'ar-kw': Alphabets.arabic,
  'ar-lb': Alphabets.arabic,
  'ar-ly': Alphabets.arabic,
  'ar-ma': Alphabets.arabic,
  'ar-om': Alphabets.arabic,
  'ar-qa': Alphabets.arabic,
  'ar-sa': Alphabets.arabic,
  'ar-sy': Alphabets.arabic,
  'ar-tn': Alphabets.arabic,
  'ar-ae': Alphabets.arabic,
  'ar-ye': Alphabets.arabic,
  'la': Alphabets.latin,
  'af': Alphabets.latin,
  'sq': Alphabets.latin,
  'an': Alphabets.latin,
  'ast': Alphabets.latin,
  'eu': Alphabets.latin,
  'br': Alphabets.latin,
  'en': Alphabets.latin,
  'en-au': Alphabets.latin,
  'en-bz': Alphabets.latin,
  'en-ca': Alphabets.latin,
  'en-ie': Alphabets.latin,
  'en-jm': Alphabets.latin,
  'en-nz': Alphabets.latin,
  'en-ph': Alphabets.latin,
  'en-za': Alphabets.latin,
  'en-tt': Alphabets.latin,
  'en-gb': Alphabets.latin,
  'en-us': Alphabets.latin,
  'en-zw': Alphabets.latin,
  'es': Alphabets.latin,
  'es-ar': Alphabets.latin,
  'es-bo': Alphabets.latin,
  'es-cl': Alphabets.latin,
  'es-co': Alphabets.latin,
  'es-cr': Alphabets.latin,
  'es-do': Alphabets.latin,
  'es-ec': Alphabets.latin,
  'es-sv': Alphabets.latin,
  'es-gt': Alphabets.latin,
  'es-hn': Alphabets.latin,
  'es-mx': Alphabets.latin,
  'es-ni': Alphabets.latin,
  'es-pa': Alphabets.latin,
  'es-py': Alphabets.latin,
  'es-pe': Alphabets.latin,
  'es-pr': Alphabets.latin,
  'es-es': Alphabets.latin,
  'es-uy': Alphabets.latin,
  'es-ve': Alphabets.latin,
  'ts': Alphabets.latin,
  'uk': Alphabets.latin,
  'wa': Alphabets.latin,
  'xh': Alphabets.latin,
  'zu': Alphabets.latin,
};
