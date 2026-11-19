import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// The sign-in goes in a header (never in the address). The library sends a ping every 25 s and drops the link if no answer comes,
/// so a phone that lost its signal is noticed and reconnects.
WebSocketChannel connectStationSocket(Uri uri, String token) => IOWebSocketChannel.connect(
  uri,
  headers: {'Authorization': 'Bearer $token'},
  pingInterval: const Duration(seconds: 25),
  connectTimeout: const Duration(seconds: 12),
);
