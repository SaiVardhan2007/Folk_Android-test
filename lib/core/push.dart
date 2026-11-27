import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app.dart';
import '../features/auth/auth_controller.dart';
import 'api.dart';

String? _token;

/// Phone notifications (Firebase). Once a coordinator or admin is signed in, this phone's token is sent to the server,
/// which uses it for "contacts assigned" and the Friday reminder. If Firebase is not set up in this build, nothing happens.
final pushProvider = Provider<void>((ref) {
  final me = ref.watch(authProvider).value;
  if (kIsWeb || me == null || !me.isStaff) return;
  var stopped = false;
  StreamSubscription<String>? refresh;
  StreamSubscription<RemoteMessage>? opened;
  ref.onDispose(() {
    stopped = true;
    refresh?.cancel();
    opened?.cancel();
  });

  Future<void> send(String t) async {
    _token = t;
    try {
      await ref.read(apiProvider).post('/devices', body: {'token': t});
    } catch (_) {} // sent again the next time the app opens
  }

  void open(RemoteMessage m) {
    final route = m.data['route'];
    if (route is String && route.startsWith('/')) ref.read(routerProvider).go(route);
  }

  () async {
    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();
      final fm = FirebaseMessaging.instance;
      await fm.requestPermission();
      // ignore: deprecated_member_use
      final t = await fm.getToken(); // the token is what Firebase's standard HTTP v1 send targets
      if (stopped) return;
      if (t != null) await send(t);
      // ignore: deprecated_member_use
      refresh = fm.onTokenRefresh.listen(send);
      opened = FirebaseMessaging.onMessageOpenedApp.listen(open);
      final first = await fm.getInitialMessage();
      if (first != null) open(first);
    } catch (e) {
      debugPrint('Notifications are not available: $e');
    }
  }();
});

/// Called on sign-out, before the sign-in is cleared: this phone stops receiving this person's notifications.
Future<void> forgetPushToken(Api api) async {
  final t = _token;
  if (t == null) return;
  _token = null;
  try {
    await api.post('/devices/remove', body: {'token': t});
  } catch (_) {}
}
