import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api.dart';
import '../../core/cache.dart';
import '../../core/models.dart';

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

  Future<void> login(String mob, String password) async =>
      _accept(await ref.read(apiProvider).post('/auth/login', body: {'mob': mob, 'password': password}));

  /// Returns a message when the account was created but still needs admin approval (the user is not signed in yet).
  Future<String?> signup({
    required String mob,
    required String password,
    required String name,
    String level = '',
    String gender = '',
    String occupation = '',
  }) async {
    final res = await ref
        .read(apiProvider)
        .post('/auth/signup', body: {'mob': mob, 'password': password, 'name': name, 'level': level, 'gender': gender, 'occupation': occupation});
    if (res['pending'] == true) return res['message'] as String? ?? 'Your account is waiting for admin approval.';
    await _accept(res);
    return null;
  }

  Future<void> activate(String mob, String code, String password) async =>
      _accept(await ref.read(apiProvider).post('/auth/activate', body: {'mob': mob, 'code': code, 'password': password}));

  Future<void> signOut() async {
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
