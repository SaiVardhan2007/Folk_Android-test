import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/layout.dart';
import '../../core/widgets.dart';
import '../auth/auth_controller.dart';
import 'admin_repo.dart';

/// One downloadable table. [allOnly] ones cannot be narrowed to a single event.
class _Dataset {
  const _Dataset(this.key, this.label, this.path, this.file, {this.allOnly = false, this.query = const {}});
  final String key, label, path, file;
  final bool allOnly;
  final Map<String, dynamic> query;
}

const _datasets = [
  _Dataset('people', 'People (all contacts)', '/admin/export/people', 'folk-people', allOnly: true),
  _Dataset('reg', 'Registrations', '/admin/export/registrations', 'folk-registrations'),
  _Dataset('vol', 'Volunteers', '/admin/export/registrations', 'folk-volunteers', query: {'kind': 'Volunteers'}),
  _Dataset('att', 'Attendance', '/admin/export/attendance', 'folk-attendance'),
  _Dataset('asg', 'Assigned calls', '/admin/export/assignments', 'folk-assigned-calls'),
  _Dataset('calls', 'Call log', '/admin/export/calls', 'folk-calls'),
  _Dataset('fb', 'Feedback', '/admin/export/feedback', 'folk-feedback'),
  _Dataset('log', 'Activity log', '/admin/export/logs', 'folk-activity-log', allOnly: true),
];

/// Admin → Settings → Download data: everything, or only some tables for one event, as CSV files.
class DownloadDataScreen extends ConsumerStatefulWidget {
  const DownloadDataScreen({super.key});
  @override
  ConsumerState<DownloadDataScreen> createState() => _DownloadDataScreenState();
}

class _DownloadDataScreenState extends ConsumerState<DownloadDataScreen> {
  String _event = ''; // empty = all events
  final Set<String> _picked = {'reg'};
  bool _busy = false;

  Future<void> _download(List<_Dataset> sets) async {
    setState(() => _busy = true);
    try {
      final suffix = _event.isEmpty ? '' : '-$_event';
      await ref.read(adminRepoProvider).shareCsvs([
        for (final d in sets)
          (path: d.path, name: '${d.file}${d.allOnly ? '' : suffix}.csv', query: {...d.query, if (_event.isNotEmpty && !d.allOnly) 'event': _event}),
      ]);
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } catch (_) {
      if (mounted) showMessage(context, 'Could not download. Try again.', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final boot = ref.watch(bootstrapProvider).value;
    final events = boot?.eventsAndLists ?? const [];
    final shown = [
      for (final d in _datasets)
        if (!(d.allOnly && _event.isNotEmpty)) d,
    ];
    final chosen = [
      for (final d in shown)
        if (_picked.contains(d.key)) d,
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Download data')),
      body: SafeArea(
        child: PageBody(
          children: [
            DropdownButtonFormField<String>(
              key: ValueKey(_event),
              initialValue: _event,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Event', prefixIcon: Icon(Icons.event_outlined)),
              items: [
                const DropdownMenuItem(value: '', child: Text('All events')),
                for (final e in events)
                  DropdownMenuItem(
                    value: e.code,
                    child: Text(e.name, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) => setState(() => _event = v ?? ''),
            ),
            const SectionTitle('What to download'),
            Card(
              child: Column(
                children: [
                  for (final d in shown)
                    CheckboxListTile(
                      value: _picked.contains(d.key),
                      title: Text(d.label),
                      onChanged: _busy ? null : (v) => setState(() => v == true ? _picked.add(d.key) : _picked.remove(d.key)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: kGapM),
            FilledButton.icon(
              onPressed: _busy || chosen.isEmpty ? null : () => _download(chosen),
              icon: _busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : const Icon(Icons.download_rounded),
              label: Text(chosen.length > 1 ? 'Download selected (${chosen.length} files)' : 'Download selected'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            ),
            const SizedBox(height: kGapS),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _download(shown),
              icon: const Icon(Icons.cloud_download_outlined),
              label: Text(_event.isEmpty ? 'Download everything' : 'Download everything for this event'),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            ),
          ],
        ),
      ),
    );
  }
}
