import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _lastKey = 'folk_last_printer';

/// Blank paper added under the receipt (in printer dots, 8 per mm) so the last lines clear the tear-off bar.
/// It is part of the picture itself: small portable printers ignore feed commands, but they always print a picture.
const int kReceiptFeedDots = 80;

enum PrinterKind { bluetooth, usb }

class PrinterDevice {
  const PrinterDevice(this.kind, this.name, this.id);
  final PrinterKind kind;
  final String name, id;
  String get label => kind == PrinterKind.usb ? '$name (USB)' : name;
}

class PrinterException implements Exception {
  PrinterException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Talks to a thermal receipt printer (ESC/POS) over Bluetooth or USB through the native bridge (PrinterBridge.kt).
class PrinterService {
  static const _ch = MethodChannel('folk/printer');

  Future<T> _call<T>(String m, [Map<String, Object?>? args]) async {
    try {
      return (await _ch.invokeMethod<T>(m, args)) as T;
    } on PlatformException catch (e) {
      throw PrinterException(e.message ?? 'Printer error');
    }
  }

  /// "granted" | "denied" | "blocked" (blocked = the user must allow it in the app settings).
  Future<String> bluetoothPermission() => _call<String>('bluetoothPermission');

  Future<void> openAppSettings() => _call<bool>('openAppSettings');

  Future<List<PrinterDevice>> bluetoothDevices() async {
    final l = await _call<List<Object?>>('listBluetooth');
    return [for (final m in l.cast<Map>()) PrinterDevice(PrinterKind.bluetooth, m['name'] as String, m['id'] as String)];
  }

  Future<List<PrinterDevice>> usbDevices() async {
    final l = await _call<List<Object?>>('listUsb');
    return [for (final m in l.cast<Map>()) PrinterDevice(PrinterKind.usb, m['name'] as String, m['id'] as String)];
  }

  Future<bool> get isConnected async => ((await _call<Map>('status'))['connected'] as bool?) ?? false;

  Future<String> get connectedName async => ((await _call<Map>('status'))['name'] as String?) ?? '';

  Future<void> connect(PrinterDevice d) async {
    await _call<bool>(d.kind == PrinterKind.usb ? 'connectUsb' : 'connectBluetooth', {'id': d.id});
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_lastKey, [d.kind.name, d.name, d.id]);
  }

  Future<void> disconnect() => _call<bool>('disconnect');

  Future<PrinterDevice?> lastUsed() async {
    final v = (await SharedPreferences.getInstance()).getStringList(_lastKey);
    if (v == null || v.length != 3) return null;
    return PrinterDevice(PrinterKind.values.firstWhere((k) => k.name == v[0], orElse: () => PrinterKind.bluetooth), v[1], v[2]);
  }

  /// Quietly reconnects to the printer used last time. Returns false if it is off, out of range or unplugged.
  Future<bool> reconnectLast() async {
    if (await isConnected) return true;
    final d = await lastUsed();
    if (d == null) return false;
    try {
      await connect(d);
      return true;
    } on PrinterException {
      return false;
    }
  }

  Future<void> _write(Uint8List data) => _call<bool>('write', {'data': data});

  /// Converts the picture to 1-bit and prints it (ESC/POS raster, in small slices the printer handles reliably), then feeds and cuts.
  Future<void> printImage(ui.Image image, {int threshold = 150}) async {
    final bd = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final w = image.width, h = image.height;
    final bytesPerRow = (w + 7) ~/ 8;
    final rgba = bd!.buffer.asUint8List();
    final total = h + kReceiptFeedDots;
    final out = Uint8List(bytesPerRow * total); // the extra rows stay 0 = blank paper
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = (y * w + x) * 4;
        final a = rgba[i + 3] / 255.0;
        final l = (0.299 * rgba[i] + 0.587 * rgba[i + 1] + 0.114 * rgba[i + 2]) * a + 255 * (1 - a);
        if (l < threshold) out[y * bytesPerRow + (x >> 3)] |= 0x80 >> (x & 7);
      }
    }

    await _write(Uint8List.fromList([0x1B, 0x40])); // initialise
    const rows = 40;
    for (var y = 0; y < total; y += rows) {
      final n = (total - y) < rows ? (total - y) : rows;
      final header = [0x1D, 0x76, 0x30, 0x00, bytesPerRow & 255, bytesPerRow >> 8, n & 255, n >> 8];
      await _write(Uint8List.fromList([...header, ...out.sublist(y * bytesPerRow, (y + n) * bytesPerRow)]));
      await Future.delayed(const Duration(milliseconds: 250));
    }
    await Future.delayed(const Duration(milliseconds: 600)); // let the printer finish moving paper before the cut
    await _write(Uint8List.fromList([0x1D, 0x56, 0x42, 0x00])); // feed to the cut position + partial cut (ignored by printers without a cutter)
  }
}

final printerServiceProvider = Provider<PrinterService>((ref) => PrinterService());
