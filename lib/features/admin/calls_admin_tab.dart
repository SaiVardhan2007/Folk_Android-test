import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_controller.dart';
import 'admin_repo.dart';
import 'assign/assign_wizard.dart';
import 'templates_editor.dart';
import '../../core/layout.dart';

/// Coordinators with their counts for the event being worked on.
final _callersProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String?>(
  (ref, event) async => (await ref.read(adminRepoProvider).callers(event: event)).callers,
);

/// Which event or contact list the admin is working on in this tab (kept apart from the Home/Attendance event).
class _CallTarget extends Notifier<String?> {
  String? _picked;
  @override
  String? build() {
    final boot = ref.watch(bootstrapProvider).value;
    final all = boot?.events ?? const <FolkEvent>[];
    final p = _picked;
    if (p != null && all.any((e) => e.code == p)) return p;
    return boot?.currentEvent;
  }

  void select(String code) {
    _picked = code;
    state = code;
  }
}

final _callTargetProvider = NotifierProvider<_CallTarget, String?>(_CallTarget.new);
final _statsProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, event) => ref.read(adminRepoProvider).callStats(event));

/// Admin → Calls: who is calling, assigning contacts to coordinators, follow-ups, message text and call statistics.
class CallsAdminTab extends ConsumerWidget {
  const CallsAdminTab({super.key});

  void _refresh(WidgetRef ref) {
    ref.invalidate(_callersProvider);
    ref.invalidate(_statsProvider);
  }

  Future<void> _openAssign(BuildContext context, WidgetRef ref, String event, Bootstrap? boot, {bool reassign = false, String? moveFrom}) async {
    final name = boot?.eventsAndLists.where((e) => e.code == event).firstOrNull?.name ?? event;
    final done = await Navigator.of(context, rootNavigator: true).push<bool>(
      MaterialPageRoute(
        builder: (_) => AssignWizard(event: event, eventName: name, reassignUnstarted: reassign, moveFromMob: moveFrom),
      ),
    );
    if (done == true) _refresh(ref);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final event = ref.watch(_callTargetProvider);
    final boot = ref.watch(bootstrapProvider).value;
    final callers = ref.watch(_callersProvider(event));

    return PageBody(
      onRefresh: () async => _refresh(ref),
      children: [
        if (boot != null && boot.events.isNotEmpty)
          DropdownButtonFormField<String>(
            key: ValueKey(event),
            initialValue: boot.events.any((e) => e.code == event) ? event : boot.events.first.code,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Calls for', prefixIcon: Icon(Icons.event_outlined)),
            items: [
              for (final e in boot.events)
                DropdownMenuItem(
                  value: e.code,
                  child: Text(e.name, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) => v == null ? null : ref.read(_callTargetProvider.notifier).select(v),
          ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.icon(
              onPressed: event == null ? null : () => _openAssign(context, ref, event, boot),
              icon: const Icon(Icons.assignment_ind_outlined),
              label: const Text('Assign calls'),
            ),
            OutlinedButton.icon(
              onPressed: event == null ? null : () => _openAssign(context, ref, event, boot, reassign: true),
              icon: const Icon(Icons.swap_horiz),
              label: const Text('Reassign Unstarted'),
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: context.colors.danger),
              onPressed: event == null ? null : () => _removeAll(context, ref, event, boot),
              icon: const Icon(Icons.delete_sweep_outlined),
              label: const Text('Remove all assigned'),
            ),
            OutlinedButton.icon(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                showDragHandle: true,
                builder: (c) => const _TemplatesSheet(),
              ),
              icon: const Icon(Icons.chat_outlined),
              label: const Text('WhatsApp messages'),
            ),
          ],
        ),
        if (event != null)
          ref
              .watch(_statsProvider(event))
              .when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => ErrorView(
                  message: e is ApiException ? e.message : 'Could not load statistics.',
                  onRetry: () => ref.invalidate(_statsProvider(event)),
                ),
                data: (s) {
                  final t = Map<String, dynamic>.from(s['totals'] as Map);
                  final byStatus = ((s['by_status'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionTitle('Call statistics'),
                      if (s['period'] is Map)
                        Padding(
                          padding: const EdgeInsets.only(bottom: kGapS),
                          child: Text(
                            'This week only (Monday ${_shortDate('${(s['period'] as Map)['from']}')} to Sunday ${_shortDate('${(s['period'] as Map)['to']}')})',
                            style: text.bodyMedium,
                          ),
                        ),
                      StatGrid(
                        children: [
                          StatTile(label: 'Assigned', value: t['assigned'], color: context.colors.brand),
                          StatTile(label: 'Calls made', value: t['calls'], color: context.colors.success),
                          StatTile(label: 'Positive', value: t['positive'], color: context.colors.success),
                          StatTile(label: 'Pending', value: t['pending'], color: context.colors.warning),
                        ],
                      ),
                      const SizedBox(height: kGapM),
                      if (byStatus.isNotEmpty)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              children: [
                                for (final r in byStatus)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 4),
                                    child: Row(
                                      children: [
                                        Expanded(child: Text('${r['label']}')),
                                        Text('${r['value']}', style: text.titleSmall),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
        const SectionTitle('Coordinators'),
        callers.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) =>
              ErrorView(message: e is ApiException ? e.message : 'Could not load coordinators.', onRetry: () => ref.invalidate(_callersProvider)),
          data: (list) => list.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('No coordinators yet.', style: text.bodyLarge),
                )
              : Column(
                  children: [
                    for (final c in list)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('${c['name']}', style: text.titleSmall),
                                    Text('${c['mob']}', style: text.bodyMedium),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Assigned ${c['assigned']}  •  Pending ${c['pending']}  •  Positive ${c['positive']}',
                                      style: text.bodyMedium,
                                    ),
                                    const SizedBox(height: 6),
                                    ActionChip(
                                      avatar: const Icon(Icons.speed_outlined, size: 18),
                                      label: Text(c['call_limit'] == null ? 'No max limit' : 'Max limit ${c['call_limit']}'),
                                      onPressed: () => _editLimit(context, ref, c),
                                    ),
                                  ],
                                ),
                              ),
                              Switch(value: c['enabled'] != false, onChanged: (v) => _setEnabled(context, ref, event, boot, c, v)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  /// "Remove all assigned": deletes every assignment of this event for every coordinator, including calls already made. The call history stays.
  Future<void> _removeAll(BuildContext context, WidgetRef ref, String event, Bootstrap? boot) async {
    final name = boot?.eventsAndLists.where((e) => e.code == event).firstOrNull?.name ?? event;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Remove all assigned contacts?'),
        content: Text(
          'Every contact assigned for $name will be taken away from the coordinators, including contacts already called, and they all become unassigned again. '
          'The call history stays, but these contacts will no longer count as called for this event.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: context.colors.danger),
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Remove all'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      final n = await ref.read(adminRepoProvider).unassign(event: event, all: true);
      _refresh(ref);
      if (context.mounted) showMessage(context, '$n assigned contact${n == 1 ? '' : 's'} removed.');
    } on ApiException catch (e) {
      if (context.mounted) showMessage(context, e.message, error: true);
    }
  }

  /// Switching a coordinator off hides them from every assign screen. It is refused while they still hold calls nobody has made:
  /// the admin must first move those to someone else or remove them.
  Future<void> _setEnabled(BuildContext context, WidgetRef ref, String? event, Bootstrap? boot, Map<String, dynamic> c, bool on) async {
    final repo = ref.read(adminRepoProvider);
    final mob = '${c['mob']}';
    Future<bool> save() async {
      try {
        await repo.setCaller(mob, {'enabled': on});
        _refresh(ref);
        return true;
      } on ApiException catch (e) {
        if (context.mounted) showMessage(context, e.message, error: true);
        return false;
      }
    }

    final waiting = (c['pending'] as num?)?.toInt() ?? 0;
    if (on || waiting == 0) {
      await save();
      return;
    }
    final choice = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('${c['name']} still has calls'),
        content: Text(
          '${c['name']} has $waiting call${waiting == 1 ? '' : 's'} nobody has made yet. To switch them off, first move those calls to another coordinator or remove them.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(d, 'remove'), child: const Text('Remove their calls')),
          FilledButton(onPressed: () => Navigator.pop(d, 'move'), child: const Text('Move to others')),
        ],
      ),
    );
    if (!context.mounted || choice == null) return;
    if (choice == 'move') {
      if (event != null) await _openAssign(context, ref, event, boot, moveFrom: mob);
      return;
    }
    try {
      await repo.unassign(coordinatorMob: mob);
    } on ApiException catch (e) {
      if (context.mounted) showMessage(context, e.message, error: true);
      return;
    }
    if (await save() && context.mounted) showMessage(context, '${c['name']} is switched off.');
  }

  Future<void> _editLimit(BuildContext context, WidgetRef ref, Map<String, dynamic> c) async {
    final ctl = TextEditingController(text: c['call_limit']?.toString() ?? '');
    final v = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Max limit for ${c['name']}'),
        content: TextField(
          controller: ctl,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Max contacts (empty = no limit)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(100, 48)),
            onPressed: () => Navigator.pop(d, ctl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (v == null || !context.mounted) return;
    try {
      await ref.read(adminRepoProvider).setCaller('${c['mob']}', {'call_limit': v.isEmpty ? null : int.tryParse(v)});
      ref.invalidate(_callersProvider);
    } on ApiException catch (e) {
      if (context.mounted) showMessage(context, e.message, error: true);
    }
  }
}

class _TemplatesSheet extends StatelessWidget {
  const _TemplatesSheet();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SheetBody(
      children: [
        Text('WhatsApp messages', style: text.titleLarge),
        const SizedBox(height: 4),
        const SizedBox(height: 10),
        TemplatesEditor(onSaved: () => Navigator.pop(context)),
      ],
    );
  }
}

/// "2026-11-16" -> "16 Nov".
String _shortDate(String iso) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  if (iso.length < 10) return iso;
  final m = int.tryParse(iso.substring(5, 7)) ?? 0;
  return '${int.tryParse(iso.substring(8, 10)) ?? iso.substring(8, 10)} ${m >= 1 && m <= 12 ? months[m - 1] : ''}'.trim();
}
