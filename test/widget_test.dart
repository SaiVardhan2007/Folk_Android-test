import 'package:flutter_test/flutter_test.dart';
import 'package:folk_android_app/core/util.dart';

void main() {
  test('normalizeMobile accepts common Indian formats', () {
    expect(normalizeMobile('9876543210'), '9876543210');
    expect(normalizeMobile('+91 98765 43210'), '9876543210');
    expect(normalizeMobile('098765-43210'), '9876543210');
    expect(normalizeMobile('12345'), isNull);
    expect(normalizeMobile('abc'), isNull);
  });

  test('shortTime formats ERPNext timestamps', () {
    expect(shortTime('2026-11-16 13:05:09'), '1:05 PM');
    expect(shortTime('2026-11-16 00:30:00'), '12:30 AM');
    expect(shortTime('2026-11-16 12:00:00'), '12:00 PM');
  });

  test('IST timestamp has the format the API expects', () {
    expect(RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$').hasMatch(istTimestamp()), isTrue);
    expect(firstName('  Sai   vardhan '), 'Sai');
  });
}
