import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api.dart';
import '../../core/models.dart';
import '../../core/util.dart';

const _queueKey = 'folk_offline_queue';

class MarkResult {
  const MarkResult({
    required this.status,
    required this.name,
    required this.ts,
    this.registered = false,
    this.queued = false,
    this.guide = '',
    this.guideMobile = '',
  });
  final String status; // marked | already | queued
  final String name;

  /// The person's FOLK guide and the guide's phone (for the receipt).
  final String guide, guideMobile;

  /// When the check-in happened (India time). For "already" it is this phone's time, so look the real one up.
  final String ts;
  final bool registered, queued;
}

/// A check-in waiting to be sent. [ts] is the time it really happened (India time).
class PendingMark {
  PendingMark({required this.mob, required this.event, required this.ts, this.name = '', this.edits, this.label = ''});
  final String mob, event, ts, name, label;
  final Map<String, dynamic>? edits;

  Map<String, dynamic> toJson() => {'mob': mob, 'event': event, 'ts': ts, 'name': name, 'label': label, 'edits': edits};
  factory PendingMark.fromJson(Map<String, dynamic> j) => PendingMark(
    mob: j['mob'] as String,
    event: j['event'] as String,
    ts: j['ts'] as String,
    name: j['name'] as String? ?? '',
    label: j['label'] as String? ?? '',
    edits: j['edits'] == null ? null : Map<String, dynamic>.from(j['edits'] as Map),
  );
}

/// Marks attendance. If the phone has no signal the check-in is saved on the phone and sent later,
/// so nothing is lost at the door. The server treats repeats as "already marked", so retries are safe.
class AttendanceRepo {
  AttendanceRepo(this._api);
  final Api _api;

  Future<List<Person>> search(String q) async {
    final r = await _api.get('/people/search', query: {'q': q});
    return ((r['people'] as List?) ?? const []).map((e) => Person.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  Future<Person?> lookup(String mob) async {
    final r = await _api.get('/people/$mob');
    final p = r['person'];
    return p == null ? null : Person.fromJson(Map<String, dynamic>.from(p as Map));
  }

  Future<List<AttendanceItem>> today(String event) async {
    final r = await _api.get('/attendance/today', query: {'event': event});
    return ((r['items'] as List?) ?? const []).map((e) => AttendanceItem.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  /// Who was marked on [date] ("YYYY-MM-DD") for [event].
  Future<List<AttendanceItem>> onDate(String event, String date) async {
    final r = await _api.get('/attendance/today', query: {'event': event, 'date': date});
    return ((r['items'] as List?) ?? const []).map((e) => AttendanceItem.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  Future<void> undo(String id) => _api.delete('/attendance/${Uri.encodeComponent(id)}');

  Future<MarkResult> mark({
    required String mob,
    required String event,
    Map<String, dynamic>? edits,
    Map<String, dynamic>? register,
    String label = '',
    bool allowQueue = false,
  }) async {
    final ts = istTimestamp();
    final body = {'mob': mob, 'event': event, 'ts': ts, 'edits': ?edits, ...?register};
    try {
      final r = await _api.post('/attendance', body: body);
      return MarkResult(
        status: r['status'] as String,
        name: r['name'] as String? ?? label,
        ts: ts,
        registered: r['registered'] == true,
        guide: r['guide'] as String? ?? '',
        guideMobile: r['guide_mobile'] as String? ?? '',
      );
    } on ApiException catch (e) {
      // Queued only when an admin has turned the offline queue on, and only for registered people (a new person needs the server to confirm the details).
      if (allowQueue && e.isNetwork && register == null) {
        await enqueue(PendingMark(mob: mob, event: event, ts: ts, edits: edits, label: label));
        return MarkResult(status: 'queued', name: label, ts: ts, queued: true);
      }
      rethrow;
    }
  }

  // ---- offline queue
  Future<List<PendingMark>> pending() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_queueKey);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List).map((e) => PendingMark.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _save(List<PendingMark> q) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_queueKey, jsonEncode(q.map((e) => e.toJson()).toList()));
  }

  Future<void> enqueue(PendingMark m) async {
    final q = await pending();
    if (!q.any((x) => x.mob == m.mob && x.event == m.event && x.ts.substring(0, 10) == m.ts.substring(0, 10))) q.add(m);
    await _save(q);
  }

  /// Sends queued check-ins. Returns how many were delivered. Stops at the first network failure.
  Future<int> flush() async {
    final q = await pending();
    if (q.isEmpty) return 0;
    var sent = 0;
    final left = <PendingMark>[];
    var offline = false;
    for (final m in q) {
      if (offline) {
        left.add(m);
        continue;
      }
      try {
        await _api.post('/attendance', body: {'mob': m.mob, 'event': m.event, 'ts': m.ts, if (m.edits != null) 'edits': m.edits});
        sent++;
      } on ApiException catch (e) {
        if (e.isNetwork || e.status == 401) {
          offline = true;
          left.add(m);
        }
        // Other errors (e.g. person no longer exists) cannot succeed on retry, so the item is dropped.
      }
    }
    await _save(left);
    return sent;
  }
}

final attendanceRepoProvider = Provider<AttendanceRepo>((ref) => AttendanceRepo(ref.watch(apiProvider)));

/// How many check-ins are waiting on this phone, plus automatic syncing in the background.
class PendingCount extends Notifier<int> {
  Timer? _timer;

  @override
  int build() {
    ref.onDispose(() => _timer?.cancel());
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => sync());
    Future.microtask(refresh);
    return 0;
  }

  Future<void> refresh() async => state = (await ref.read(attendanceRepoProvider).pending()).length;

  /// Tries to send everything waiting. Returns how many were delivered.
  Future<int> sync() async {
    final repo = ref.read(attendanceRepoProvider);
    if ((await repo.pending()).isEmpty) {
      state = 0;
      return 0;
    }
    final n = await repo.flush();
    await refresh();
    return n;
  }
}

final pendingCountProvider = NotifierProvider<PendingCount, int>(PendingCount.new);
