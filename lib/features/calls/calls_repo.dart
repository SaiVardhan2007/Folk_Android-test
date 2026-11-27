import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/cache.dart';

import '../../core/api.dart';

class CallItem {
  const CallItem({
    required this.id,
    required this.mob,
    required this.name,
    required this.eventName,
    required this.status,
    required this.note,
    required this.isFollowUp,
    required this.submittedAt,
    required this.assignedAt,
    required this.level,
    required this.venue,
    required this.pgName,
    required this.profession,
    required this.sessions,
    required this.calls28d,
  });
  final String id, mob, name, eventName, status, note, submittedAt, assignedAt, level, venue, pgName, profession;
  final bool isFollowUp;
  final int sessions, calls28d;

  bool get isPending => status == 'Not Done' || status.isEmpty;

  factory CallItem.fromJson(Map<String, dynamic> j) => CallItem(
    id: j['id'] as String,
    mob: j['mob'] as String? ?? '',
    name: j['name'] as String? ?? '',
    eventName: j['event_name'] as String? ?? '',
    status: j['status'] as String? ?? 'Not Done',
    note: j['note'] as String? ?? '',
    isFollowUp: j['is_follow_up'] as bool? ?? false,
    submittedAt: j['submitted_at'] as String? ?? '',
    assignedAt: j['assigned_at'] as String? ?? '',
    level: j['level'] as String? ?? '',
    venue: j['venue'] as String? ?? '',
    pgName: j['pg_name'] as String? ?? '',
    profession: j['profession'] as String? ?? '',
    sessions: (j['sessions'] as num?)?.toInt() ?? 0,
    calls28d: (j['calls_28d'] as num?)?.toInt() ?? 0,
  );
}

class CallsData {
  const CallsData({required this.items, required this.messageText, required this.statuses, required this.positive, required this.noteRequired});
  final List<CallItem> items;
  final String messageText;
  final List<String> statuses, positive, noteRequired;

  factory CallsData.fromJson(Map<String, dynamic> j) {
    List<String> list(String k) => ((j[k] as List?) ?? const []).map((e) => e.toString()).toList();
    return CallsData(
      items: ((j['items'] as List?) ?? const []).map((e) => CallItem.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      messageText: j['message_text'] as String? ?? '',
      statuses: list('statuses'),
      positive: list('positive'),
      noteRequired: list('note_required'),
    );
  }
}

class CallsRepo {
  CallsRepo(this._api);
  final Api _api;

  Future<CallsData> load() async => CallsData.fromJson(await _api.get('/my/calls'));

  /// [ref] identifies this one tap of Submit; sending it again (after a bad connection) never creates a second log row.
  Future<void> submit(String id, {required String status, required String note, required String ref}) =>
      _api.post('/my/calls/${Uri.encodeComponent(id)}/submit', body: {'status': status, 'note': note, 'client_ref': ref});

  Future<Map<String, dynamic>> history(String mob) => _api.get('/people/$mob/history');

  static String newRef() {
    final r = Random.secure();
    return List.generate(20, (_) => r.nextInt(16).toRadixString(16)).join();
  }
}

/// How long a half-finished call (called / messaged / status / note) is remembered on the phone before it is forgotten.
const kCallDraftKeep = Duration(minutes: 30);

/// What a coordinator has done on one call card but not submitted yet. Survives leaving the screen, switching apps or closing the app.
class CallDraft {
  const CallDraft({this.called = false, this.messaged = false, this.status = '', this.note = ''});
  final bool called, messaged;
  final String status, note;

  static String _key(String id) => 'call_draft:$id';

  /// The saved draft for assignment [id], or null when there is none or it is older than [kCallDraftKeep].
  static Future<CallDraft?> load(String id) async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key(id));
      if (raw == null) return null;
      final j = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final at = DateTime.fromMillisecondsSinceEpoch((j['at'] as num?)?.toInt() ?? 0);
      if (DateTime.now().difference(at) > kCallDraftKeep) {
        await p.remove(_key(id));
        return null;
      }
      return CallDraft(
        called: j['called'] == true,
        messaged: j['messaged'] == true,
        status: j['status'] as String? ?? '',
        note: j['note'] as String? ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> save(String id) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
        _key(id),
        jsonEncode({'called': called, 'messaged': messaged, 'status': status, 'note': note, 'at': DateTime.now().millisecondsSinceEpoch}),
      );
    } catch (_) {}
  }

  static Future<void> clear(String id) async {
    try {
      await (await SharedPreferences.getInstance()).remove(_key(id));
    } catch (_) {}
  }
}

final callsRepoProvider = Provider<CallsRepo>((ref) => CallsRepo(ref.watch(apiProvider)));

final callsProvider = StreamProvider.autoDispose<CallsData>((ref) => cachedGet(ref, '/my/calls', CallsData.fromJson));
