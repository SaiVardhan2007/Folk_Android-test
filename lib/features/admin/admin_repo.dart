import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api.dart';
import '../../core/models.dart';

class PeoplePage {
  const PeoplePage(this.people, this.total);
  final List<Person> people;
  final int total;
}

class AdminRepo {
  AdminRepo(this._api);
  final Api _api;

  Future<PeoplePage> people(Map<String, String> filters, int page) async {
    final r = await _api.get('/admin/people', query: {...filters, 'page': page});
    return PeoplePage(
      ((r['people'] as List?) ?? const []).map((e) => Person.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      (r['total'] as num?)?.toInt() ?? 0,
    );
  }

  Future<void> setRole(String mob, String tag) => _api.patch('/admin/people/$mob/role', body: {'tag': tag});
  Future<void> setActive(String mob, bool active) => _api.patch('/admin/people/$mob/active', body: {'active': active});

  /// Returns the one-time code to read out to the person. The old password is removed.
  Future<String> resetPassword(String mob) async => (await _api.post('/admin/people/$mob/reset'))['code'] as String;

  Future<Map<String, dynamic>> settings() async => Map<String, dynamic>.from((await _api.get('/admin/settings'))['settings'] as Map);
  Future<void> saveSettings(Map<String, dynamic> patch) => _api.put('/admin/settings', body: patch);

  // ---- calling (admin)
  Future<List<Map<String, dynamic>>> callers() async =>
      ((await _api.get('/admin/callers'))['callers'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  Future<void> setCaller(String mob, Map<String, dynamic> patch) => _api.patch('/admin/callers/$mob', body: patch);
  Future<Map<String, dynamic>> assign(Map<String, dynamic> body, {required bool preview}) =>
      _api.post(preview ? '/admin/assign/preview' : '/admin/assign', body: body);
  Future<int> unassign(String event, {String? coordinatorMob}) async =>
      ((await _api.post('/admin/assign/unassign', body: {'event': event, 'coordinator': coordinatorMob}))['removed'] as num).toInt();
  Future<Map<String, dynamic>> followUp(String event, List<String> coordinatorMobs) =>
      _api.post('/admin/assign/followup', body: {'event': event, 'coordinators': coordinatorMobs});
  Future<Map<String, dynamic>> callStats(String event) => _api.get('/admin/calls/stats', query: {'event': event});
  Future<List<Map<String, dynamic>>> templates() async =>
      ((await _api.get('/admin/templates'))['templates'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  Future<void> saveTemplates(List<Map<String, dynamic>> t) => _api.put('/admin/templates', body: {'templates': t});

  Future<void> addEvent(String code, String name, {bool isList = false}) =>
      _api.post('/admin/events', body: {'code': code, 'name': name, if (isList) 'is_list': true});
  Future<void> setCurrentEvent(String code) => _api.post('/admin/events/${Uri.encodeComponent(code)}/current');

  /// One page (50) of registrations for an event, with the totals shown at the top.
  Future<Map<String, dynamic>> registrations(Map<String, String> filters, int page) =>
      _api.get('/admin/registrations', query: {...filters, 'page': page});

  /// One page (50) of feedback answers for an event, with the total and the average rating.
  Future<Map<String, dynamic>> feedback(Map<String, String> filters, int page) => _api.get('/admin/feedback', query: {...filters, 'page': page});

  /// One page (50) of the activity log, newest first.
  Future<Map<String, dynamic>> logs(Map<String, String> filters, int page) => _api.get('/admin/logs', query: {...filters, 'page': page});

  // ---- public registration links
  Future<List<Map<String, dynamic>>> links() async => _linkList(await _api.get('/admin/links'));
  Future<void> createLink(Map<String, dynamic> body) => _api.post('/admin/links', body: body);
  Future<void> updateLink(String slug, Map<String, dynamic> patch) => _api.patch('/admin/links/$slug', body: patch);

  /// Links assigned to the signed-in person.
  Future<List<Map<String, dynamic>>> myLinks() async => _linkList(await _api.get('/my/links'));
  List<Map<String, dynamic>> _linkList(Map<String, dynamic> r) =>
      ((r['links'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  Future<Map<String, dynamic>> analytics(Map<String, String> filters) => _api.get('/admin/analytics', query: filters);

  /// Downloads a CSV and opens the phone's share sheet (save to Drive, send on WhatsApp, etc.).
  Future<void> shareCsv(String apiPath, String fileName, {Map<String, dynamic>? query}) async {
    final text = await _api.getText(apiPath, query: query);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(text);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/csv')],
        subject: fileName,
      ),
    );
  }
}

final adminRepoProvider = Provider<AdminRepo>((ref) => AdminRepo(ref.watch(apiProvider)));
