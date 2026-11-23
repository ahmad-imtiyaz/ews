import 'package:ews/config.dart';
import 'package:ews/services/report_contact.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

ReportContact _contact(http.Response Function() reply) => ReportContact(
  baseUrl: 'http://ews.test',
  client: MockClient((request) async {
    expect(request.url.path, '/api/ews/pelaporan');
    return reply();
  }),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('nomor dibaca dari balasan server', () {
    expect(
      parseReportNumber({
        'tersedia': true,
        'nomor': '6281226498705',
        'nomor_tampil': '0812-2649-8705',
      }),
      '6281226498705',
    );
    expect(
      parseReportNumber({'tersedia': true, 'nomor': '0813-1111-2222'}),
      '6281311112222',
    );
  });

  test('nomor kosong atau tidak tersedia diabaikan', () {
    expect(parseReportNumber({'tersedia': false, 'nomor': null}), isNull);
    expect(parseReportNumber({'tersedia': true, 'nomor': ''}), isNull);
    expect(parseReportNumber({'tersedia': true, 'nomor': '12345'}), isNull);
    expect(parseReportNumber({}), isNull);
  });

  test('nomor baru dari server dipakai dan disimpan', () async {
    final contact = _contact(
      () => http.Response('{"tersedia":true,"nomor":"6281311112222"}', 200),
    );
    await contact.refresh();
    expect(contact.number.value, '6281311112222');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('report.whatsapp'), '6281311112222');
  });

  test('tanpa sinyal, nomor yang tersimpan tetap dipakai', () async {
    SharedPreferences.setMockInitialValues({
      'report.whatsapp': '6281399998888',
    });
    final contact = _contact(() => throw http.ClientException('putus'));
    await contact.refresh();
    expect(contact.number.value, '6281399998888');
  });

  test(
    'nomor yang sudah pernah di-chat diingat dalam format apa pun',
    () async {
      final contact = ReportContact();
      expect(await contact.hasChatted('0857-4210-2428'), isFalse);
      await contact.markChatted('6285742102428');
      expect(await contact.hasChatted('0857-4210-2428'), isTrue);
      expect(await contact.hasChatted('6281226498705'), isFalse);
    },
  );

  test('server gagal dan belum ada simpanan: pakai nomor bawaan', () async {
    final contact = _contact(() => http.Response('error', 500));
    await contact.refresh();
    expect(contact.number.value, reportWhatsAppNumber);
  });
}
