import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/auth/auth_controller.dart';
import 'api.dart';

const _prefix = 'c1:';

/// Remembers the last server answer for each screen, in memory and on the phone.
/// Screens show it instantly (even offline) and then quietly replace it with fresh data.
class JsonCache {
  final Map<String, Map<String, dynamic>> _mem = {};
  final Set<String> _fetched = {}; // keys already refreshed from the server during this app run
  SharedPreferences? _prefs;

  Future<SharedPreferences> get _p async => _prefs ??= await SharedPreferences.getInstance();

  Future<Map<String, dynamic>?> get(String key) async {
    final hit = _mem[key];
    if (hit != null) return hit;
    final raw = (await _p).getString('$_prefix$key');
    if (raw == null) return null;
    try {
      return _mem[key] = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  bool fetchedThisRun(String key) => _fetched.contains(key);

  Future<void> put(String key, Map<String, dynamic> value) async {
    _mem[key] = value;
    _fetched.add(key);
    try {
      await (await _p).setString('$_prefix$key', jsonEncode(value));
    } catch (_) {}
  }

  /// Called on sign-out so the next person never sees the previous person's data.
  Future<void> clear() async {
    _mem.clear();
    _fetched.clear();
    final p = await _p;
    for (final k in p.getKeys().where((k) => k.startsWith(_prefix)).toList()) {
      await p.remove(k);
    }
  }
}

final jsonCacheProvider = Provider<JsonCache>((ref) => JsonCache());

/// Stale-while-revalidate: emits the saved copy at once (if any), then the fresh answer.
/// If the fresh request fails but a saved copy was shown, the saved copy stays on screen.
Stream<T> cachedGet<T>(Ref ref, String path, T Function(Map<String, dynamic>) parse, {Map<String, dynamic>? query}) async* {
  final me = ref.read(authProvider).value?.id ?? '';
  final key =
      '$me|$path|${query == null ? '' : (query.entries.toList()..sort((a, b) => a.key.compareTo(b.key))).map((e) => '${e.key}=${e.value}').join('&')}';
  final cache = ref.read(jsonCacheProvider);
  var shown = false;
  // The saved copy is only shown the first time in a run; later refreshes keep the data already on screen, so lists never flicker.
  final saved = cache.fetchedThisRun(key) ? null : await cache.get(key);
  if (saved != null) {
    try {
      yield parse(saved);
      shown = true;
    } catch (_) {}
  }
  try {
    final fresh = await ref.read(apiProvider).get(path, query: query);
    cache.put(key, fresh);
    yield parse(fresh);
  } on ApiException {
    if (shown) return;
    final fallback = await cache.get(key); // refresh failed (offline): keep showing the last good copy
    if (fallback == null) rethrow;
    yield parse(fallback);
  }
}
