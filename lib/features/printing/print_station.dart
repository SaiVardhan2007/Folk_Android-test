import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../core/api.dart';
import '../../core/config.dart';
import '../auth/auth_controller.dart';
import 'printer_service.dart';
import 'receipt_format.dart';
import 'receipt_renderer.dart';
import 'station_socket.dart';

/// Turns the phone that is connected to the printer into the printing phone for everyone, with nothing to switch on.
///
/// While a coordinator's phone has the printer connected (and the app is open), it keeps one connection to the server. Receipts marked on any
/// phone wait in the server's queue; the server sends them down this connection one at a time, and this phone prints each and confirms it.
/// When the printer is disconnected, the app goes to the background or the user signs out, the connection closes and the queue waits for the
/// next phone that connects to a printer. The screen is kept awake while this is active, otherwise the phone would sleep and stop printing.
class PrintStation with WidgetsBindingObserver {
  PrintStation(this._ref) {
    WidgetsBinding.instance.addObserver(this);
    _changes = _ref.read(printerServiceProvider).connectionChanges.listen((_) => _sync());
    _ref.listen(authProvider, (_, _) => _sync());
    _sync();
  }

  final Ref _ref;
  late final StreamSubscription<bool> _changes;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _messages;
  Timer? _retry;
  int _failures = 0;
  bool _foreground = true, _starting = false, _disposed = false;

  PrinterService get _printer => _ref.read(printerServiceProvider);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _foreground = true;
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden || state == AppLifecycleState.detached) _foreground = false;
    _sync();
  }

  /// Starts or stops the connection to match: signed in as staff + printer connected + app open.
  Future<void> _sync() async {
    if (_disposed || kIsWeb) return;
    final staff = _ref.read(authProvider).value?.isStaff ?? false;
    final want = staff && _foreground && await _printer.isConnected;
    if (want) {
      await _open();
    } else {
      _close();
    }
  }

  Future<void> _open() async {
    if (_channel != null || _starting || _disposed) return;
    _starting = true;
    try {
      final token = await _ref.read(tokenStoreProvider).read();
      if (token == null) return;
      final uri = Uri.parse('${kApiBaseUrl.replaceFirst('https://', 'wss://').replaceFirst('http://', 'ws://')}/print/station');
      final channel = connectStationSocket(uri, token);
      await channel.ready;
      if (_disposed) {
        channel.sink.close();
        return;
      }
      _channel = channel;
      _failures = 0;
      unawaited(WakelockPlus.enable());
      _messages = channel.stream.listen(_onMessage, onDone: _onClosed, onError: (_) => _onClosed());
    } catch (_) {
      _scheduleRetry();
    } finally {
      _starting = false;
    }
  }

  void _close() {
    _retry?.cancel();
    _messages?.cancel();
    _messages = null;
    _channel?.sink.close();
    _channel = null;
    unawaited(WakelockPlus.disable());
  }

  void _onClosed() {
    _messages?.cancel();
    _messages = null;
    _channel = null;
    _scheduleRetry();
  }

  /// Tries again with growing pauses (2, 4, 8, 16, 30 s), and only while this phone should still be printing.
  void _scheduleRetry() {
    if (_disposed) return;
    _retry?.cancel();
    final seconds = [2, 4, 8, 16, 30][_failures.clamp(0, 4)];
    _failures++;
    _retry = Timer(Duration(seconds: seconds), _sync);
  }

  void _send(Map<String, Object?> m) {
    try {
      _channel?.sink.add(jsonEncode(m));
    } catch (_) {
      // the connection dropped: the server hands the receipt to someone else
    }
  }

  Future<void> _onMessage(dynamic raw) async {
    final Map<String, dynamic> m;
    try {
      m = Map<String, dynamic>.from(jsonDecode(raw as String) as Map);
    } catch (_) {
      return;
    }
    if (m['type'] != 'job') return;
    final id = m['id'];
    final d = Map<String, dynamic>.from(m['data'] as Map);
    try {
      final boot = _ref.read(bootstrapProvider).value;
      final image = await renderReceipt(
        boot?.receipt ?? const ReceiptFormat(),
        ReceiptData(
          name: '${d['name'] ?? ''}',
          mob: '${d['mob'] ?? ''}',
          event: '${d['event'] ?? ''}',
          ts: '${d['ts'] ?? ''}',
          count: (d['count'] as num?)?.toInt() ?? 0,
          markedBy: '${d['marked_by'] ?? ''}',
        ),
      );
      await _printer.printImage(image);
      await Future.delayed(const Duration(milliseconds: 1500)); // time for the paper to come out before the next one starts
      _send({'type': 'done', 'id': id});
    } catch (_) {
      await _printer.disconnect().catchError((_) {}); // the printer is off, out of paper or out of range: stop being the printing phone
      _send({'type': 'failed', 'id': id});
    }
  }

  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _changes.cancel();
    _close();
  }
}

/// Watched once by the app frame (app_shell.dart) so it runs for as long as someone is signed in.
final printStationProvider = Provider<PrintStation>((ref) {
  final s = PrintStation(ref);
  ref.onDispose(s.dispose);
  return s;
});
