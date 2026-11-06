/// Jenis tanda yang dipakai NLP, CNN, dan pilihan warga. [code] sama dengan
/// label di `assets/nlp/contoh_laporan.csv` dan `assets/models/labels.txt`.
enum SignCategory {
  retakan('retakan', 'Retakan tanah'),
  longsoran('longsoran', 'Longsoran'),
  rembesan('rembesan', 'Rembesan air'),
  pohonMiring('pohon_miring', 'Pohon atau tiang miring'),
  gemuruh('gemuruh', 'Suara gemuruh'),
  tidakRelevan('tidak_relevan', 'Tidak terkait longsor');

  const SignCategory(this.code, this.label);

  final String code;
  final String label;

  static SignCategory? fromCode(String code) {
    for (final category in values) {
      if (category.code == code.trim()) return category;
    }
    return null;
  }
}
