import 'package:flutter_test/flutter_test.dart';
import 'package:folk_android_app/features/printing/receipt_format.dart';
import 'package:folk_android_app/features/printing/receipt_renderer.dart';

void main() {
  const data = ReceiptData(name: 'Test Person', mob: '9876543210', event: 'Sunday', ts: '2026-11-18 10:30:00', count: 2);

  test('receipt is printer-width and shorter when fields are hidden', () async {
    final full = await renderReceipt(const ReceiptFormat(), data);
    final slim = await renderReceipt(const ReceiptFormat(showEvent: false, showPhone: false, showTime: false, showCount: false, footer: ''), data);
    expect(full.width, kReceiptWidth);
    expect(slim.height, lessThan(full.height));
  });

  test('format survives a JSON round trip and falls back to defaults', () {
    const f = ReceiptFormat(title: 'HKM', showMarkedBy: true);
    final back = ReceiptFormat.fromJson(f.toJson());
    expect(back.title, 'HKM');
    expect(back.showMarkedBy, isTrue);
    expect(ReceiptFormat.fromJson(null).title, 'FOLK');
  });
}
