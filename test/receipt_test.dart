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

  test('typed text round-trips; older settings still build the same layout', () {
    const f = ReceiptFormat(text: 'Flower packets: {name}', showLogo: false);
    final back = ReceiptFormat.fromJson(f.toJson());
    expect(back.text, 'Flower packets: {name}');
    expect(back.showLogo, isFalse);
    expect(ReceiptFormat.fromJson(null).layout, contains('{name}'));
    expect(ReceiptFormat.fromJson({'show_marked_by': true}).layout, contains('{marked_by}'));
  });

  test('typed fields are filled in and empty lines are left out', () async {
    final v = receiptValues(data);
    expect(v['name'], 'Test Person');
    expect(v['date'], '18-11-2026');
    expect(v['count'], '2 times');
    expect(v['marked_by'], '');
    final a = await renderReceipt(const ReceiptFormat(text: '{name}\nMarked by: {marked_by}', showLogo: false), data);
    final b = await renderReceipt(const ReceiptFormat(text: '{name}', showLogo: false), data);
    expect(a.height, b.height); // the "Marked by" line has no value, so it is not printed
  });
}
