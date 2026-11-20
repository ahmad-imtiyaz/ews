import 'dart:math' as math;

import 'package:flutter/services.dart';

import 'sign_category.dart';

const dictionaryAsset = 'assets/nlp/kamus_lumeneng.csv';
const generalDictionaryAsset = 'assets/nlp/kamus_ngapak_umum.csv';
const examplesAsset = 'assets/nlp/contoh_laporan.csv';
const placesAsset = 'assets/nlp/nama_tempat.csv';

/// Di bawah angka ini kategori teks ditampilkan sebagai "belum yakin".
/// Angka awal, belum dikalibrasi dengan laporan nyata.
const textConfidenceThreshold = 0.6;

final _tokenPattern = RegExp(
  r"[\p{L}\p{N}]+(?:[-'][\p{L}\p{N}]+)*|[.,!?;:]",
  unicode: true,
);
final _punctuation = RegExp(r'^[.,!?;:]$');

const _negators = {'tidak', 'belum', 'bukan', 'tanpa', 'jangan'};

const _stopwords = {
  'di',
  'ke',
  'dari',
  'yang',
  'dan',
  'itu',
  'ini',
  'ada',
  'dengan',
  'juga',
  'saja',
  'pak',
  'bu',
  'mbah',
  'rt',
  'rw',
  'saya',
  'kamu',
  'sudah',
  'sekali',
  'sangat',
  'agak',
  'tadi',
  'tadinya',
  'sekarang',
  'kemarin',
  'malam',
  'pagi',
  'siang',
  'sore',
  'sejak',
  'jam',
  'makin',
  'lagi',
  'ya',
  'kok',
  'pun',
  'para',
  'oleh',
  'untuk',
  'pada',
  'karena',
  'atau',
  'seperti',
  'semua',
  'sendiri',
  'dua',
  'tiga',
  'menjadi',
  'ikut',
  'padahal',
  'terus',
};

const _placeStarters = {
  'di',
  'dekat',
  'belakang',
  'depan',
  'samping',
  'sebelah',
  'pinggir',
  'atas',
  'bawah',
  'sekitar',
  'seberang',
  'sisi',
};

/// Akhiran Jawa, yang panjang dicoba lebih dulu. -e/-ne ditangani terpisah.
const _javaSuffixes = ['kna', 'ake', 'na', 'an', 'ku', 'mu', 'i'];

/// Awalan nasal dan huruf awal kata dasar yang mungkin luluh:
/// nyapu <- sapu, ngombe <- ombe, mbukak <- bukak, nulis <- tulis.
const _nasalPrefixes = [
  ('ng', ['', 'k']),
  ('ny', ['s', 'c']),
  ('m', ['', 'p', 'w']),
  ('n', ['', 't']),
];
final _derivedStandard = RegExp(r'^(me|ber|ter|di)');

const _placeStoppers = {
  'retak',
  'longsor',
  'runtuh',
  'amblas',
  'miring',
  'roboh',
  'tumbang',
  'merembes',
  'keluar',
  'sekarang',
  'tadi',
  'kemarin',
  'makin',
  'sudah',
  'terus',
  'sejak',
  'dan',
  'karena',
  'saat',
  'waktu',
  'yang',
  'tidak',
  'belum',
  'ada',
  'tidak ada',
  'menutupi',
  'menutup',
};

const _changeMarkers = {
  'makin',
  'semakin',
  'bertambah',
  'meluas',
  'melebar',
  'membesar',
  'baru',
  'terus',
  'bergerak',
  'bergeser',
};

/// Akibat langsung bagi warga, misalnya jalan tertutup.
const _impactMarkers = {
  'menutupi',
  'menutup',
  'tertutup',
  'menimbun',
  'tertimbun',
  'tertimpa',
  'putus',
  'jebol',
  'roboh',
  'terperosok',
};
const _nowMarkers = {'sekarang', 'barusan', 'tadi'};
const _intensityMarkers = {
  'lebar',
  'besar',
  'banyak',
  'deras',
  'keras',
  'parah',
  'panjang',
  'dalam',
  'sekali',
  'sangat',
  'licin',
};

enum Urgency {
  tinggi('Tinggi'),
  sedang('Sedang'),
  biasa('Biasa');

  const Urgency(this.label);

  final String label;
}

class NlpToken {
  const NlpToken(this.original, this.normalized, {this.merged = false});

  final String original;

  /// Kosong bila kata dibuang (partikel) atau digabung ke kata sebelumnya.
  final String normalized;

  /// Kata ini digabung ke kata sebelumnya, misalnya "lemah e" menjadi
  /// "tanahnya". Bila [normalized] kosong dan ini `false`, katanya dibuang.
  final bool merged;

  bool get isPunctuation => _punctuation.hasMatch(original);
  bool get changed => normalized.toLowerCase() != original.toLowerCase();
}

class TextAnalysis {
  const TextAnalysis({
    required this.original,
    required this.caseFolded,
    required this.tokens,
    required this.standardized,
    required this.features,
    required this.probabilities,
    required this.place,
    required this.urgency,
    required this.urgencyMarkers,
    this.unknownWords = const [],
  });

  final String original;
  final String caseFolded;
  final List<NlpToken> tokens;
  final String standardized;

  /// Kata setelah stopword dibuang, stemming, dan penandaan penyangkalan.
  final List<String> features;

  /// Kosong bila tidak satu pun kata dikenal model.
  final Map<SignCategory, double> probabilities;
  final String? place;
  final Urgency urgency;
  final List<String> urgencyMarkers;

  /// Kata yang tidak ada di kamus maupun data latih, untuk ditambahkan ke
  /// kamus. Bisa juga kata Indonesia yang belum dipakai di contoh laporan.
  final List<String> unknownWords;

  MapEntry<SignCategory, double>? get _top => probabilities.isEmpty
      ? null
      : probabilities.entries.reduce((a, b) => a.value >= b.value ? a : b);

  SignCategory? get category => _top?.key;
  double? get confidence => _top?.value;
  bool get isConfident => (confidence ?? 0) >= textConfidenceThreshold;

  List<NlpToken> get changedTokens =>
      tokens.where((t) => !t.isPunctuation && t.changed).toList();
}

/// Pipeline NLP di HP: case folding, tokenisasi, normalisasi kamus lokal,
/// stopword, stemming ringan, lalu klasifikasi Naive Bayes multinomial.
class TextAnalyzer {
  TextAnalyzer._(
    this._dictionary,
    this._standardWords,
    this._places,
    this._model,
  );

  factory TextAnalyzer.fromCsv({
    required String dictionaryCsv,
    required String examplesCsv,
    String generalDictionaryCsv = '',
    String placesCsv = '',
  }) {
    // Kamus tanda longsor dimuat terakhir supaya artinya yang dipakai.
    final dictionary = <String, String>{};
    for (final csv in [generalDictionaryCsv, dictionaryCsv]) {
      for (final (local, standard) in _csvRows(csv)) {
        dictionary[local.toLowerCase()] = standard;
      }
    }
    final standardWords = {
      for (final value in dictionary.values)
        ...value.toLowerCase().split(' ').where((w) => w.isNotEmpty),
    };

    final places = {
      for (final line in placesCsv.split('\n'))
        if (line.trim().isNotEmpty && !line.trim().startsWith('#'))
          line.trim().toLowerCase(): line.trim(),
    };

    final analyzer = TextAnalyzer._(
      dictionary,
      standardWords,
      places,
      _NaiveBayes(),
    );
    for (final (label, text) in _csvRows(examplesCsv)) {
      final category = SignCategory.fromCode(label);
      if (category == null) continue;
      final tokens = analyzer._normalize(analyzer._tokenize(text));
      analyzer._model.add(category, _features(tokens));
    }
    return analyzer;
  }

  static Future<TextAnalyzer> load([AssetBundle? bundle]) async {
    final assets = bundle ?? rootBundle;
    return TextAnalyzer.fromCsv(
      dictionaryCsv: await assets.loadString(dictionaryAsset),
      generalDictionaryCsv: await assets.loadString(generalDictionaryAsset),
      examplesCsv: await assets.loadString(examplesAsset),
      placesCsv: await assets.loadString(placesAsset),
    );
  }

  final Map<String, String> _dictionary;
  final Set<String> _standardWords;

  /// Nama tempat dalam huruf kecil -> penulisan yang benar.
  final Map<String, String> _places;
  final _NaiveBayes _model;

  int get dictionarySize => _dictionary.length;
  int get trainingSize => _model.documents;

  TextAnalysis analyze(String text) {
    final tokens = _normalize(_tokenize(text));
    final features = _features(tokens);
    final words = [
      for (final token in tokens)
        if (token.normalized.isNotEmpty) token.normalized,
    ];
    final probabilities = _model.predict(features);
    final topIsIrrelevant =
        probabilities.isNotEmpty &&
        probabilities.entries
                .reduce((a, b) => a.value >= b.value ? a : b)
                .key ==
            SignCategory.tidakRelevan;
    final (urgency, markers) = topIsIrrelevant
        ? (Urgency.biasa, const <String>[])
        : _urgency(words);

    return TextAnalysis(
      original: text,
      caseFolded: text.toLowerCase(),
      tokens: tokens,
      standardized: _sentence(tokens),
      features: features,
      probabilities: probabilities,
      place: _place(words),
      urgency: urgency,
      urgencyMarkers: markers,
      unknownWords: _unknownWords(tokens),
    );
  }

  List<String> _unknownWords(List<NlpToken> tokens) {
    final unknown = <String>{};
    for (final (index, token) in tokens.indexed) {
      if (token.isPunctuation || token.changed) continue;
      final word = token.original.toLowerCase();
      // Kapital yang dibiarkan di tengah kalimat berarti nama atau singkatan.
      final sentenceStart = index == 0 || tokens[index - 1].isPunctuation;
      if (token.normalized != word && !sentenceStart) continue;
      if (word.length < 3 || word.contains(RegExp(r'\d'))) continue;
      if (_dictionary.containsKey(word) ||
          _standardWords.contains(word) ||
          _stopwords.contains(word) ||
          _negators.contains(word) ||
          _model.knows(_stem(word))) {
        continue;
      }
      unknown.add(word);
    }
    return unknown.toList();
  }

  List<String> _tokenize(String text) =>
      _tokenPattern.allMatches(text).map((m) => m.group(0)!).toList();

  List<NlpToken> _normalize(List<String> raw) {
    final letters = raw.join().replaceAll(
      RegExp(r'[^\p{L}]', unicode: true),
      '',
    );
    final upper = letters.replaceAll(RegExp(r'[^\p{Lu}]', unicode: true), '');
    // Tombol caps lock menyala: singkatan pun tidak bisa dibedakan.
    final shouting = letters.length >= 8 && upper.length / letters.length > 0.6;

    final normalized = <String>[];
    final merged = <int>{};
    for (final (index, original) in raw.indexed) {
      final folded = original.toLowerCase();
      final previousIsWord =
          index > 0 &&
          normalized.last.isNotEmpty &&
          !_punctuation.hasMatch(raw[index - 1]);

      // "lemah e" ditulis terpisah: akhiran -e/-ne menjadi -nya.
      if ((folded == 'e' || folded == 'ne') && previousIsWord) {
        normalized[index - 1] = '${normalized[index - 1]}nya';
        normalized.add('');
        merged.add(index);
        continue;
      }
      normalized.add(_normalizeWord(original, folded, shouting));
    }
    return [
      for (final (index, original) in raw.indexed)
        NlpToken(original, normalized[index], merged: merged.contains(index)),
    ];
  }

  String _normalizeWord(String original, String folded, bool shouting) {
    final direct = _dictionary[folded];
    if (direct != null) return direct;
    final place = _places[folded];
    if (place != null) return place;

    for (final suffix in const ['ne', 'e']) {
      if (!folded.endsWith(suffix)) continue;
      final root = folded.substring(0, folded.length - suffix.length);
      if (root.length < 3) continue;
      final standard =
          _dictionary[root] ?? (_standardWords.contains(root) ? root : null);
      if (standard != null && standard.isNotEmpty) return '${standard}nya';
    }
    return _fromAffixes(folded) ?? _fixCase(original, folded, shouting);
  }

  /// Kata dasar minimal 4 huruf agar "ana" tidak ditemukan di "diana".
  String? _root(String root) {
    if (root.length < 4) return null;
    final standard = _dictionary[root];
    return standard == null || standard.isEmpty ? null : standard;
  }

  String? _withoutSuffix(String word) {
    final direct = _root(word);
    if (direct != null) return direct;
    for (final suffix in _javaSuffixes) {
      if (!word.endsWith(suffix)) continue;
      final standard = _root(word.substring(0, word.length - suffix.length));
      if (standard == null) continue;
      // bengkahan -> retakan, omahku -> rumahku; -na/-i cukup kata dasarnya.
      final keepsSuffix = const {'an', 'ku', 'mu'}.contains(suffix);
      return keepsSuffix && !standard.contains(' ')
          ? '$standard$suffix'
          : standard;
    }
    return null;
  }

  /// Kata berimbuhan Jawa yang kata dasarnya ada di kamus:
  /// digawa -> dibawa, kegawa -> terbawa, nggawakna -> bawa.
  String? _fromAffixes(String word) {
    if (_standardWords.contains(word)) return null;
    final suffixed = _withoutSuffix(word);
    if (suffixed != null) return suffixed;

    for (final (prefix, standardPrefix) in const [
      ('di', 'di'),
      ('ke', 'ter'),
    ]) {
      if (!word.startsWith(prefix)) continue;
      final standard = _withoutSuffix(word.substring(prefix.length));
      if (standard == null) continue;
      final isBase =
          !standard.contains(' ') && !_derivedStandard.hasMatch(standard);
      return isBase ? '$standardPrefix$standard' : standard;
    }

    for (final (prefix, initials) in _nasalPrefixes) {
      if (!word.startsWith(prefix)) continue;
      final rest = word.substring(prefix.length);
      for (final initial in initials) {
        final standard = _withoutSuffix('$initial$rest');
        if (standard != null) return standard;
      }
    }
    return null;
  }

  /// Kata di luar kamus: huruf acak seperti "tIkUnGaN" dijadikan kecil.
  /// Kata berawalan kapital (nama orang) dan singkatan pendek dibiarkan.
  static String _fixCase(String original, String folded, bool shouting) {
    if (original == folded || original.length < 2) return original;
    final rest = original.substring(1);
    final isTitle =
        original[0] != original[0].toLowerCase() && rest == rest.toLowerCase();
    if (isTitle) return original;
    final isAcronym =
        original == original.toUpperCase() && original.length <= 5;
    if (isAcronym && !shouting) return original;
    return folded;
  }

  String _sentence(List<NlpToken> tokens) {
    final buffer = StringBuffer();
    for (final token in tokens) {
      if (token.normalized.isEmpty) continue;
      if (!token.isPunctuation && buffer.isNotEmpty) buffer.write(' ');
      buffer.write(token.normalized);
    }
    var sentence = buffer.toString().replaceAllMapped(
      RegExp(r'(^|[.!?]\s+)(\p{Ll})', unicode: true),
      (m) => '${m[1]}${m[2]!.toUpperCase()}',
    );
    if (sentence.isNotEmpty &&
        !_punctuation.hasMatch(sentence[sentence.length - 1])) {
      sentence = '$sentence.';
    }
    return sentence;
  }

  String? _place(List<String> words) {
    final lower = [for (final w in words) w.toLowerCase()];
    final start = lower.indexWhere(_placeStarters.contains);
    if (start < 0) return null;

    final picked = <String>[];
    for (var i = start; i < words.length && picked.length < 6; i++) {
      final word = lower[i];
      if (_punctuation.hasMatch(word) || _placeStoppers.contains(word)) break;
      picked.add(words[i]);
    }
    if (picked.isNotEmpty && const {'di', 'ke'}.contains(picked.first)) {
      picked.removeAt(0);
    }
    return picked.isEmpty ? null : picked.join(' ');
  }

  (Urgency, List<String>) _urgency(List<String> words) {
    final markers = <String>[];
    var score = 0;
    for (final (index, raw) in words.indexed) {
      final word = raw.toLowerCase();
      if (index > 0 && _negators.contains(words[index - 1].toLowerCase())) {
        continue;
      }
      final weight =
          _changeMarkers.contains(word) || _impactMarkers.contains(word)
          ? 2
          : _nowMarkers.contains(word) || _intensityMarkers.contains(word)
          ? 1
          : 0;
      if (weight == 0 || markers.contains(word)) continue;
      markers.add(word);
      score += weight;
    }
    final urgency = score >= 3
        ? Urgency.tinggi
        : score >= 1
        ? Urgency.sedang
        : Urgency.biasa;
    return (urgency, markers);
  }

  static List<String> _features(List<NlpToken> tokens) {
    final features = <String>[];
    var negate = false;
    for (final token in tokens) {
      if (token.isPunctuation) {
        negate = false;
        continue;
      }
      for (final raw in token.normalized.toLowerCase().split(' ')) {
        if (raw.isEmpty) continue;
        if (_negators.contains(raw)) {
          negate = true;
          continue;
        }
        if (_stopwords.contains(raw)) continue;
        final word = _stem(raw);
        features.add(negate ? 'tidak_$word' : word);
        negate = false;
      }
    }
    return features;
  }

  // Stemming ringan: hanya akhiran kepemilikan dan partikel.
  static String _stem(String word) {
    for (final suffix in const ['nya', 'lah', 'kah']) {
      if (word.endsWith(suffix) && word.length - suffix.length >= 3) {
        return word.substring(0, word.length - suffix.length);
      }
    }
    return word;
  }

  static Iterable<(String, String)> _csvRows(String csv) sync* {
    for (final line in csv.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final comma = trimmed.indexOf(',');
      if (comma <= 0) continue;
      yield (
        trimmed.substring(0, comma).trim(),
        trimmed.substring(comma + 1).trim(),
      );
    }
  }
}

class _NaiveBayes {
  final _documents = <SignCategory, int>{};
  final _wordCounts = <SignCategory, Map<String, int>>{};
  final _totalWords = <SignCategory, int>{};
  final _vocabulary = <String>{};

  int get documents => _documents.values.fold(0, (a, b) => a + b);

  bool knows(String word) => _vocabulary.contains(word);

  void add(SignCategory category, List<String> features) {
    _documents.update(category, (n) => n + 1, ifAbsent: () => 1);
    final counts = _wordCounts.putIfAbsent(category, () => {});
    for (final word in features) {
      counts.update(word, (n) => n + 1, ifAbsent: () => 1);
      _vocabulary.add(word);
    }
    _totalWords.update(
      category,
      (n) => n + features.length,
      ifAbsent: () => features.length,
    );
  }

  Map<SignCategory, double> predict(List<String> features) {
    final known = features.where(_vocabulary.contains).toList();
    if (known.isEmpty || _documents.isEmpty) return const {};

    final total = documents;
    final logScores = <SignCategory, double>{};
    for (final category in _documents.keys) {
      final counts = _wordCounts[category]!;
      final denominator = _totalWords[category]! + _vocabulary.length;
      var score = math.log(_documents[category]! / total);
      for (final word in known) {
        score += math.log(((counts[word] ?? 0) + 1) / denominator);
      }
      logScores[category] = score;
    }

    final best = logScores.values.reduce(math.max);
    final exp = {
      for (final e in logScores.entries) e.key: math.exp(e.value - best),
    };
    final sum = exp.values.fold(0.0, (a, b) => a + b);
    return {for (final e in exp.entries) e.key: e.value / sum};
  }
}
