import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api.dart';
import '../../core/cache.dart';
import '../../core/models.dart';
import '../../core/push.dart';

const _userKey = 'folk_user';
const _bootKey = 'folk_bootstrap';

/// Who is signed in (null = signed out). Works offline: the last known user is remembered on the phone.
class AuthController extends AsyncNotifier<Person?> {
  @override
  Future<Person?> build() async {
    final api = ref.read(apiProvider);
    api.onUnauthorized = () => signOut();
    final token = await ref.read(tokenStoreProvider).read();
    if (token == null) return null;
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_userKey);
    Person? cached;
    if (saved != null) {
      try {
        cached = Person.fromJson(Map<String, dynamic>.from(jsonDecode(saved) as Map));
      } catch (_) {}
    }
    try {
      final me = await api.get('/me');
      final u = me['user'];
      if (u == null) {
        await signOut();
        return null;
      }
      final p = Person.fromJson(Map<String, dynamic>.from(u as Map));
      // A renewed session comes with every app start, so people who use the app are never signed out.
      final renewed = me['token'];
      if (renewed is String && renewed.isNotEmpty) await ref.read(tokenStoreProvider).write(renewed);
      await prefs.setString(_userKey, jsonEncode(p.toJson()));
      return p;
    } on ApiException catch (e) {
      if (e.isNetwork && cached != null) return cached; // offline: open the app with the last known user
      if (e.status == 401) {
        await signOut();
        return null;
      }
      return cached;
    }
  }

  Future<void> _accept(Map<String, dynamic> res) async {
    await ref.read(tokenStoreProvider).write(res['token'] as String);
    final p = Person.fromJson(Map<String, dynamic>.from(res['user'] as Map));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, jsonEncode(p.toJson()));
    state = AsyncData(p);
  }

  /// Asks for a Coordinator account (no password). Returns whether it is approved already, and a message to show.
  Future<({bool approved, String message})> signup({required String mob, required String name, String level = '', String gender = ''}) async {
    final res = await ref.read(apiProvider).post('/auth/signup', body: {'mob': mob, 'name': name, 'level': level, 'gender': gender});
    return (approved: res['approved'] == true, message: res['message'] as String? ?? '');
  }

  /// Sign in, step 1: texts a 6-digit code to the number. [appHash] lets Android read the SMS without asking.
  /// Returns true when the SMS carries the app hash, so the app can read it with no prompt.
  Future<bool> sendOtp(String mob, {String appHash = ''}) async =>
      (await ref.read(apiProvider).post('/auth/otp/send', body: {'mob': mob, 'app_hash': appHash}))['auto_read'] == true;

  /// Step 2: the right code signs the person in.
  Future<void> verifyOtp(String mob, String otp) async =>
      _accept(await ref.read(apiProvider).post('/auth/otp/verify', body: {'mob': mob, 'otp': otp}));

  Future<void> signOut() async {
    await forgetPushToken(ref.read(apiProvider));
    await ref.read(tokenStoreProvider).clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userKey);
    await prefs.remove(_bootKey);
    await ref.read(jsonCacheProvider).clear();
    state = const AsyncData(null);
  }
}

final authProvider = AsyncNotifierProvider<AuthController, Person?>(AuthController.new);

/// Events, allowed values for forms, and the current event. Saved on the phone, so the app opens instantly and works offline.
final bootstrapProvider = StreamProvider<Bootstrap>((ref) {
  final user = ref.watch(authProvider).value;
  if (user == null) return Stream.error(ApiException('Not signed in'));
  return cachedGet(ref, '/bootstrap', Bootstrap.fromJson);
});

/// The event the volunteer is working on (shared by Home, Attendance and Register). Defaults to the current event.
/// A choice made by the user is kept when fresh data arrives.
class SelectedEvent extends Notifier<String?> {
  String? _picked;

  @override
  String? build() {
    final boot = ref.watch(bootstrapProvider).value;
    final p = _picked;
    if (p != null && (boot == null || boot.events.any((e) => e.code == p))) return p;
    return boot?.currentEvent;
  }

  void select(String code) {
    _picked = code;
    state = code;
  }
}

final selectedEventProvider = NotifierProvider<SelectedEvent, String?>(SelectedEvent.new);
