/// Comprehensive gazetteer and phonetic normalizer for Lagos, Nigeria.
///
/// Solves two core problems in voice navigation for Nigerian English:
/// 1. Provides an acoustic proper-noun prompt ([whisperPrompt]) for Whisper STT
///    so Yoruba and Nigerian English place names are favored during decoding.
/// 2. Normalizes common phonetic transcriptions and fuzzy-matches spoken
///    Lagos neighborhoods, bus stops, markets, and landmarks in < 1 ms.
class LagosGazetteer {
  const LagosGazetteer._();

  /// Concise proper-noun vocabulary hint for `whisper-large-v3-turbo` (kept
  /// strictly to rare Nigerian/Lagos proper nouns and acronyms so Whisper never
  /// hallucinates conversational sentence continuations).
  static const String whisperPrompt =
      'Ikotun, Shomolu, Egbeda, Iyana Ipaja, Gbagada, Mushin, Agege, Abule Egba, '
      'Ojota, Ketu, Oyingbo, Obalende, Ikoyi, Victoria Island, Lekki Phase 1, '
      'Ologolo, Ajah, Sangotedo, Ikorodu, Ikeja, Alausa, Ojodu Berger, Yaba, '
      'UNILAG, Surulere, Ojuelegba, Oshodi, Isolo, Festac, LASU, Okokomaiko, '
      'MTN, Airtel, GTBank, UBA, NIN, BVN, VFS Global, NIMC, FRSC.';

  /// Canonical Lagos places, areas, bus stops, and landmarks.
  static const List<String> canonicalPlaces = [
    // Alimosho / West
    'Ikotun',
    'Ikotun Egbe',
    'Igando',
    'Egbeda',
    'Idimu',
    'Isheri Olofin',
    'Iyana Ipaja',
    'Ipaja',
    'Ayobo',
    'Abule Egba',
    'Ekoro',
    'Meiran',
    'Alagbado',
    'Command',
    'Baruwa',
    'Gowon Estate',
    'Shasha',
    'Akowonjo',
    'Dopemu',
    'Iyana Dopemu',
    'Cement',
    'Mangoro',
    'Alimosho',
    // Somolu / Kosofe / Mainland
    'Shomolu',
    'Bariga',
    'Gbagada',
    'Gbagada Phase 1',
    'Gbagada Phase 2',
    'Pedro',
    'Onipanu',
    'Palmgrove',
    'Fadeyi',
    'Jibowu',
    'Yaba',
    'Sabo Yaba',
    'Akoka',
    'UNILAG',
    'Tejuosho',
    'Ojuelegba',
    'Surulere',
    'Bode Thomas',
    'Adeniran Ogunsanya',
    'Aguda',
    'Ijesha',
    'Lawanson',
    'Itire',
    'Mushin',
    'Idi Oro',
    'Papa Ajao',
    'Ilupeju',
    'Anthony',
    'Anthony Village',
    'Mende',
    'Maryland',
    'Ojota',
    'Ogudu',
    'Ogudu GRA',
    'Alapere',
    'Ketu',
    'Mile 12',
    'Owode Onirin',
    'Ebute Metta',
    'Oyingbo',
    'Costain',
    'Iganmu',
    // Ikeja / Agege / North
    'Ikeja',
    'Ikeja GRA',
    'Ikeja City Mall',
    'MTN office, Ikeja',
    'Alausa',
    'Allen Avenue',
    'Opebi',
    'Toyin Street',
    'Computer Village',
    'Awolowo Way',
    'Oba Akran',
    'Ogba',
    'Agidingbi',
    'Omole Phase 1',
    'Omole Phase 2',
    'Magodo',
    'Magodo Phase 1',
    'Magodo Phase 2',
    'Shangisha',
    'Ojodu Berger',
    'Berger',
    'Isheri',
    'Olowora',
    'Agege',
    'Pen Cinema',
    'Oko Oba',
    'Ifako',
    'Iju Ishaga',
    'Fagba',
    // Oshodi / Isolo / Amuwo / Badagry Axis
    'Oshodi',
    'Mafoluku',
    'Airport Road',
    'Ajao Estate',
    'Isolo',
    'Ago Palace Way',
    'Okota',
    'Cele',
    'Ejigbo',
    'Jakande Estate',
    'Bucknor',
    'Mile 2',
    'Festac Town',
    'Amuwo Odofin',
    'Trade Fair',
    'Alaba International',
    'Ojo',
    'LASU',
    'Iba',
    'Iyana Iba',
    'Okokomaiko',
    'Agbara',
    'Badagry',
    'Orile',
    'Coker',
    'Agboju',
    'Satellite Town',
    'Navy Town',
    'Kirikiri',
    'Apapa',
    'Tin Can',
    'Ajegunle',
    // Lagos Island / Ikoyi / VI / Lekki / Epe Axis
    'Lagos Island',
    'Marina',
    'CMS',
    'Broad Street',
    'Balogun Market',
    'Idumota',
    'Adeniji Adele',
    'Obalende',
    'Ikoyi',
    'Falomo',
    'Banana Island',
    'Dolphin Estate',
    'Osborne',
    'Victoria Island',
    'Ahmadu Bello Way',
    'Adeola Odeku',
    'Eko Hotel',
    'Oniru',
    'Lekki Phase 1',
    'Lekki',
    'Admiralty Way',
    'Marwa',
    'Ikate',
    'Elegushi',
    'Ologolo',
    'Ologolo bus stop',
    'Agungi',
    'Osapa London',
    'Jakande',
    'Igbo Efon',
    'Chevron',
    'Orchid Road',
    'Ikota',
    'VGC',
    'Victoria Garden City',
    'Ajah',
    'Ilaje',
    'Badore',
    'Ado',
    'Langbasa',
    'Abraham Adesanya',
    'Ogombo',
    'Sangotedo',
    'Abijo',
    'Awoyaya',
    'Lakowe',
    'Bogije',
    'Ibeju Lekki',
    'Eleko',
    'Epe',
    // Ikorodu Axis
    'Ikorodu',
    'Ikorodu Garage',
    'Agric',
    'Benson',
    'Igbogbo',
    'Ijede',
    'Imota',
    'Majidun',
    'Ogolonto',
    'Owutu',
    // Major Lagos Institutions, Offices & Hubs
    'MTN office, Ikeja',
    'MTN office, Victoria Island',
    'MTN office, Lekki',
    'MTN office, Surulere',
    'MTN office',
    'Airtel Office',
    'Glo Office',
    '9mobile Office',
    'GTBank',
    'Access Bank',
    'Zenith Bank',
    'FirstBank',
    'UBA',
    'Ikoyi Passport Office',
    'Alausa Passport Office',
    'Festac Passport Office',
    'NIMC Office, Alausa',
    'NIMC Office',
    'FRSC Office, Ojodu',
    'FRSC Office',
    'VFS Global, Ikeja',
    'VFS Global, Lekki',
    'VFS Global',
    'US Consulate, Victoria Island',
    'British Deputy High Commission',
    'LUTH, Idi-Araba',
    'LASUTH, Ikeja',
    'Reddington Hospital',
    'Lagoon Hospital',
    'Evercare Hospital, Lekki',
    'Landmark Beach',
    'Landmark Event Centre',
  ];

  /// Direct phonetic and multi-word mishearing replacements applied to raw
  /// STT transcripts before routing or LLM resolution.
  static const Map<String, String> _phoneticPhraseReplacements = {
    // Ikotun variants
    'he caught on': 'Ikotun',
    'he caught in': 'Ikotun',
    'i caught on': 'Ikotun',
    'we caught on': 'Ikotun',
    'ekotun': 'Ikotun',
    'i kotun': 'Ikotun',
    'e kotun': 'Ikotun',
    'ikotun egbe': 'Ikotun Egbe',
    'ikotun': 'Ikotun',
    'hikotun': 'Ikotun',
    'ikoto': 'Ikotun',
    'ecotun': 'Ikotun',
    'eco tune': 'Ikotun',
    'iko tun': 'Ikotun',
    // Shomolu / Somolu variants
    'show more loo': 'Shomolu',
    'so more loo': 'Shomolu',
    'shomolo': 'Shomolu',
    'somolo': 'Shomolu',
    'somolu': 'Shomolu',
    'sho mo lu': 'Shomolu',
    'shawmolu': 'Shomolu',
    'shamolu': 'Shomolu',
    // Iyana Ipaja variants
    'ayana paja': 'Iyana Ipaja',
    'iyana paja': 'Iyana Ipaja',
    'yana paja': 'Iyana Ipaja',
    'iana ipaja': 'Iyana Ipaja',
    'iyana ipaja': 'Iyana Ipaja',
    // Egbeda variants
    'agbeda': 'Egbeda',
    'ebeda': 'Egbeda',
    'egbada': 'Egbeda',
    'egg beda': 'Egbeda',
    // Gbagada variants
    'bagada': 'Gbagada',
    'ba gada': 'Gbagada',
    'gbada': 'Gbagada',
    // Abule Egba variants
    'abulegba': 'Abule Egba',
    'abule egba': 'Abule Egba',
    'abu legba': 'Abule Egba',
    'abule iba': 'Abule Egba',
    // Ojodu Berger variants
    'ojodu baja': 'Ojodu Berger',
    'ojodu burger': 'Ojodu Berger',
    // Oshodi variants
    'oshody': 'Oshodi',
    'o shodi': 'Oshodi',
    'osodi': 'Oshodi',
    // Surulere variants
    'suru lere': 'Surulere',
    'shurulere': 'Surulere',
    'suulere': 'Surulere',
    // Ojuelegba variants
    'oju elegba': 'Ojuelegba',
    'ojuelegba': 'Ojuelegba',
    // Okokomaiko variants
    'okoko maiko': 'Okokomaiko',
    'okoko michael': 'Okokomaiko',
    // Sangotedo variants
    'sango tedo': 'Sangotedo',
    'shango tedo': 'Sangotedo',
    'shangotedo': 'Sangotedo',
    // Ologolo variants
    'olo golo': 'Ologolo',
    'ologolo': 'Ologolo',
    'hollow golo': 'Ologolo',
    // Lekki variants
    'leki phase one': 'Lekki Phase 1',
    'lekki phase one': 'Lekki Phase 1',
    'leki': 'Lekki',
    // Ikeja variants
    'ekeja': 'Ikeja',
    'i keja': 'Ikeja',
    'ikeja city more': 'Ikeja City Mall',
    // Ikorodu variants
    'e korodu': 'Ikorodu',
    'ikorodu': 'Ikorodu',
    'ekorodu': 'Ikorodu',
    // Obalende / Oyingbo / Yaba / Mushin / Agege / Ketu / Ajah
    'oba lende': 'Obalende',
    'oyinbo': 'Oyingbo',
    'oyingbo': 'Oyingbo',
    'mu shin': 'Mushin',
    'mushing': 'Mushin',
    'a gege': 'Agege',
    'ke tu': 'Ketu',
    'a jah': 'Ajah',
    'vi': 'Victoria Island',
    'v.i.': 'Victoria Island',
    'unilag': 'UNILAG',
    'lasu': 'LASU',
    // Nigerian Telecoms, Banks, Government & Errand Terms
    'empty end': 'MTN',
    'empty and': 'MTN',
    'em tee en': 'MTN',
    'm t n': 'MTN',
    'm.t.n.': 'MTN',
    'air tell': 'Airtel',
    'hair tell': 'Airtel',
    'nine mobile': '9mobile',
    'g t bank': 'GTBank',
    'gt bank': 'GTBank',
    'g t b': 'GTBank',
    'gtb': 'GTBank',
    'first bank': 'FirstBank',
    'u b a': 'UBA',
    'en eye en': 'NIN',
    'n i n': 'NIN',
    'bee vee en': 'BVN',
    'b v n': 'BVN',
    'seem card': 'SIM card',
    'seam card': 'SIM card',
    'scene card': 'SIM card',
    'seem swap': 'SIM swap',
    'seam swap': 'SIM swap',
    'v f s': 'VFS Global',
    'f r s c': 'FRSC',
    'n i m c': 'NIMC',
    'lasra': 'LASSRA',
    'lassra': 'LASSRA',
  };

  /// Rewrites known Nigerian English / Yoruba place mishearings in [utterance]
  /// into their canonical Lagos names.
  static String normalizeTranscript(String utterance) {
    if (utterance.trim().isEmpty) return utterance;
    var result = utterance;
    for (final entry in _phoneticPhraseReplacements.entries) {
      final pattern = RegExp(
        r'\b' + RegExp.escape(entry.key) + r'\b',
        caseSensitive: false,
      );
      if (pattern.hasMatch(result)) {
        result = result.replaceAll(pattern, entry.value);
      }
    }
    return result;
  }

  /// Attempts to match [candidate] (either a full short utterance like
  /// `"Ikotun"` or a destination phrase like `"shomolu bus stop"`) against
  /// [canonicalPlaces] using exact, prefix, and phonetic/Levenshtein similarity.
  static String? matchPlace(String candidate) {
    final normalized = normalizeTranscript(candidate).trim();
    if (normalized.isEmpty) return null;

    final lower = normalized
        .toLowerCase()
        .replaceAll(RegExp(r"[^\w\s]"), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (lower.isEmpty) return null;

    // 1. Exact canonical match (case-insensitive)
    for (final place in canonicalPlaces) {
      final placeClean = place
          .toLowerCase()
          .replaceAll(RegExp(r"[^\w\s]"), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (placeClean == lower) return place;
    }

    // 2. Strip trailing generic suffixes like "bus stop", "area", "lagos", "road"
    // and connecting prepositions like "in" / "at" (e.g. "MTN office in Ikeja").
    final stripped = lower
        .replaceFirst(
          RegExp(r'\s+(?:bus\s+stop|under\s+bridge|garage|lagos|area|axis)$'),
          '',
        )
        .replaceAll(RegExp(r'\b(?:in|at)\s+'), '')
        .trim();
    for (final place in canonicalPlaces) {
      final placeClean = place
          .toLowerCase()
          .replaceAll(RegExp(r"[^\w\s]"), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (placeClean == stripped) {
        return lower.endsWith('bus stop') &&
                !place.toLowerCase().endsWith('bus stop')
            ? '$place bus stop'
            : place;
      }
    }

    // 3. Phonetic skeleton / edit-distance match for single- or two-word place names
    final words = stripped.split(' ');
    if (words.length <= 3 && stripped.length >= 4) {
      final skeleton = _phoneticSkeleton(stripped);
      String? bestPlace;
      var bestDistance = 99;

      for (final place in canonicalPlaces) {
        final placeLower = place.toLowerCase();
        final placeSkeleton = _phoneticSkeleton(placeLower);
        if (skeleton.isNotEmpty && skeleton == placeSkeleton) {
          return place;
        }
        final dist = _levenshtein(stripped, placeLower);
        final maxAllowed = stripped.length <= 5 ? 1 : 2;
        if (dist <= maxAllowed && dist < bestDistance) {
          bestDistance = dist;
          bestPlace = place;
        }
      }
      if (bestPlace != null) return bestPlace;
    }

    // 4. If the candidate names a specific venue/institution plus a Lagos area
    // (e.g. "MTN office in Ikeja" or "GTBank Lekki Phase 1"), preserve both the
    // venue and the canonical area rather than collapsing to just the area name.
    final hasSpecificVenue = RegExp(
      r'\b(?:mtn|airtel|glo|9mobile|gtbank|access|zenith|firstbank|uba|bank|office|passport|nimc|frsc|vfs|consulate|embassy|hospital|clinic|mall|market|hotel|beach|university|station|airport)\b',
      caseSensitive: false,
    ).hasMatch(lower);

    String? longestMatch;
    for (final place in canonicalPlaces) {
      final placeLower = place
          .toLowerCase()
          .replaceAll(RegExp(r"[^\w\s]"), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      final regex = RegExp(r'\b' + RegExp.escape(placeLower) + r'\b');
      if (regex.hasMatch(lower)) {
        if (longestMatch == null || place.length > longestMatch.length) {
          longestMatch = place;
        }
      }
    }
    if (hasSpecificVenue && longestMatch != null) {
      // If longestMatch already includes the venue (e.g. "MTN Office, Ikeja"), return it.
      if (RegExp(
        r'\b(?:mtn|airtel|glo|9mobile|gtbank|access|zenith|firstbank|uba|passport|nimc|frsc|vfs|consulate|commission|luth|lasuth|hospital|landmark)\b',
        caseSensitive: false,
      ).hasMatch(longestMatch)) {
        return longestMatch;
      }
      // Otherwise preserve the normalized candidate string (e.g. "MTN office in Surulere").
      return normalized;
    }
    return longestMatch;
  }

  /// Reduces a word to its Nigerian-English phonetic consonant/vowel skeleton
  /// so "shomolu" == "somolu", "ikotun" == "ekotun", "gbagada" == "bagada".
  static String _phoneticSkeleton(String input) {
    return input
        .toLowerCase()
        .replaceAll('sh', 's')
        .replaceAll('gb', 'b')
        .replaceAll('kp', 'p')
        .replaceAll('ph', 'f')
        .replaceAll('ck', 'k')
        .replaceAll('c', 'k')
        .replaceAll('q', 'k')
        .replaceAll(RegExp(r'^e(?=k|g|b|j)'), 'i')
        .replaceAll(RegExp(r'h'), '')
        .replaceAll(RegExp(r'(.)\1+'), r'$1')
        .replaceAll(' ', '');
  }

  static int _levenshtein(String s, String t) {
    if (s == t) return 0;
    if (s.isEmpty) return t.length;
    if (t.isEmpty) return s.length;

    final v0 = List<int>.generate(t.length + 1, (i) => i);
    final v1 = List<int>.filled(t.length + 1, 0);

    for (var i = 0; i < s.length; i++) {
      v1[0] = i + 1;
      for (var j = 0; j < t.length; j++) {
        final cost = s.codeUnitAt(i) == t.codeUnitAt(j) ? 0 : 1;
        var min = v1[j] + 1;
        final del = v0[j + 1] + 1;
        final sub = v0[j] + cost;
        if (del < min) min = del;
        if (sub < min) min = sub;
        v1[j + 1] = min;
      }
      for (var j = 0; j <= t.length; j++) {
        v0[j] = v1[j];
      }
    }
    return v0[t.length];
  }
}

