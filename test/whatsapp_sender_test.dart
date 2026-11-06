import 'package:ews/services/whatsapp_sender.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('nomor lokal dan internasional diubah ke format WhatsApp', () {
    expect(internationalPhone('081226498705'), '6281226498705');
    expect(internationalPhone('0812-2649-8705'), '6281226498705');
    expect(internationalPhone('+62 812 2649 8705'), '6281226498705');
    expect(internationalPhone('6281226498705'), '6281226498705');
  });

  test('nomor ditampilkan dalam format lokal', () {
    expect(localPhone('6281226498705'), '0812-2649-8705');
    expect(localPhone('081226498705'), '0812-2649-8705');
  });
}
