import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../core/util.dart';
import 'receipt_format.dart';

/// Paper width in dots (58 mm roll, 48 mm printable, 203 dpi).
const int kReceiptWidth = 384;
const double _pad = 8;
const _ink = Color(0xFF000000);

/// The FOLK logo printed at the top. The picture has empty margins, so only this part of it (x, y, width, height) is drawn.
const _logoAsset = 'assets/images/folk_receipt_logo.webp';
const _logoCrop = Rect.fromLTWH(6, 32, 228, 171);
const double _logoWidth = 230;
Future<ui.Image?>? _logo;

Future<ui.Image?> _loadLogo() => _logo ??= () async {
  try {
    final bytes = (await rootBundle.load(_logoAsset)).buffer.asUint8List();
    final codec = await ui.instantiateImageCodec(bytes);
    return (await codec.getNextFrame()).image;
  } catch (_) {
    return null; // no logo: the text title is printed instead
  }
}();

/// Draws the receipt as a black-and-white picture, ready for the thermal printer.
/// Drawn directly with a canvas (no widgets on screen), so it works from any button.
Future<ui.Image> renderReceipt(ReceiptFormat f, ReceiptData d) async {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  var y = 12.0;

  double text(String s, {double size = 26, bool bold = false, TextAlign align = TextAlign.center}) {
    if (s.trim().isEmpty) return 0;
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(color: _ink, fontFamily: 'Poppins', fontSize: size, fontWeight: bold ? FontWeight.w700 : FontWeight.w500, height: 1.25),
      ),
      textAlign: align,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: kReceiptWidth - _pad * 2, minWidth: kReceiptWidth - _pad * 2);
    tp.paint(canvas, Offset(_pad, y));
    y += tp.height + 4;
    return tp.height;
  }

  void rule() {
    y += 4;
    final p = Paint()
      ..color = _ink
      ..strokeWidth = 2;
    for (double x = _pad; x < kReceiptWidth - _pad; x += 12) {
      canvas.drawLine(Offset(x, y), Offset(x + 6, y), p);
    }
    y += 12;
  }

  void row(String label, String value) {
    text('$label: $value', size: 24, align: TextAlign.left);
  }

  final logo = await _loadLogo();
  if (logo != null) {
    final h = _logoWidth * _logoCrop.height / _logoCrop.width;
    canvas.drawImageRect(
      logo,
      _logoCrop,
      Rect.fromLTWH((kReceiptWidth - _logoWidth) / 2, y, _logoWidth, h),
      Paint()..filterQuality = FilterQuality.high,
    );
    y += h + 8;
  } else {
    text(f.title, size: 44, bold: true);
  }
  if (f.showEvent && d.event.isNotEmpty) text(d.event.toUpperCase(), size: 28, bold: true);
  text(f.subtitle, size: 26);
  rule();
  text(d.name.isEmpty ? d.mob : d.name, size: 34, bold: true);
  y += 4;
  if (f.showPhone && d.name.isNotEmpty) row('Phone', d.mob);
  if (f.showTime && d.ts.length >= 16) {
    row('Date', '${d.ts.substring(8, 10)}-${d.ts.substring(5, 7)}-${d.ts.substring(0, 4)}');
    row('Time', shortTime(d.ts));
  }
  if (f.showCount && d.count > 0) row('Attended', '${d.count} time${d.count == 1 ? '' : 's'}');
  if (f.showMarkedBy && d.markedBy.isNotEmpty) row('Marked by', d.markedBy);
  if (f.footer.trim().isNotEmpty) {
    rule();
    text(f.footer, size: 26, bold: true);
  }
  y += 12;

  final picture = rec.endRecording();
  final img = await picture.toImage(kReceiptWidth, y.ceil());
  // toImage leaves unpainted areas transparent; the printer code composites on white.
  return img;
}
