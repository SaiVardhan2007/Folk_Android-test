import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_controller.dart';
import 'admin_repo.dart';
import 'assign_screen.dart';
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

  Future<void> _openAssign(BuildContext context, WidgetRef ref, String event, Bootstrap? boot) async {
    final name = boot?.eventsAndLists.where((e) => e.code == event).firstOrNull?.name ?? event;
    final done = await Navigator.of(context, rootNavigator: true).push<bool>(
      MaterialPageRoute(
        builder: (_) => AssignScreen(event: event, eventName: name),
      ),
    );
    if (done == true) _refresh(ref);
  }

  Future<void> _confirmRun(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required String body,
    required String button,
    required Future<String> Function() run,
    bool danger = false,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(100, 48), backgroundColor: danger ? context.colors.danger : null),
            onPressed: () => Navigator.pop(c, true),
            child: Text(button),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      final msg = await run();
      _refresh(ref);
      if (context.mounted) showMessage(context, msg);
    } on ApiException catch (e) {
      if (context.mounted) showMessage(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final event = ref.watch(_callTargetProvider);
    final boot = ref.watch(bootstrapProvider).value;
    final callers = ref.watch(_callersProvider(event));
    final repo = ref.read(adminRepoProvider);

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
        const SizedBox(height: 14),
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
              onPressed: event == null
                  ? null
                  : () => _confirmRun(
                      context,
                      ref,
                      title: 'Remove unstarted calls?',
                      button: 'Remove',
                      danger: true,
                      body:
                          'Takes back every assigned contact nobody has called yet for this event. Contacts already called stay with their coordinator, and no history is deleted.',
                      run: () async => '${await repo.unassign(event)} call(s) removed.',
                    ),
              icon: const Icon(Icons.person_remove_outlined),
              label: const Text('Remove unstarted'),
              style: OutlinedButton.styleFrom(foregroundColor: context.colors.danger),
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
                  padding: EdgeInsets.all(24),
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
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) =>
              ErrorView(message: e is ApiException ? e.message : 'Could not load coordinators.', onRetry: () => ref.invalidate(_callersProvider)),
          data: (list) => list.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('No coordinators yet. People who sign up and are approved appear here.', style: text.bodyLarge),
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
                                      label: Text(c['call_limit'] == null ? 'No call limit' : 'Limit ${c['call_limit']}'),
                                      onPressed: () => _editLimit(context, ref, c),
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                children: [
                                  Switch(
                                    value: c['auto_assign'] == true,
                                    onChanged: (v) async {
                                      try {
                                        await repo.setCaller('${c['mob']}', {'auto_assign': v});
                                        ref.invalidate(_callersProvider);
                                      } on ApiException catch (e) {
                                        if (context.mounted) showMessage(context, e.message, error: true);
                                      }
                                    },
                                  ),
                                  Text('Auto assign', style: text.bodySmall),
                                ],
                              ),
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

  Future<void> _editLimit(BuildContext context, WidgetRef ref, Map<String, dynamic> c) async {
    final ctl = TextEditingController(text: c['call_limit']?.toString() ?? '');
    final v = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Call limit for ${c['name']}'),
        content: TextField(
          controller: ctl,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
          autofocus: true,
          decoration: const InputDecoration(helperText: 'Most contacts they can be given. Leave empty for no limit.'),
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

class _TemplatesSheet extends ConsumerStatefulWidget {
  const _TemplatesSheet();
  @override
  ConsumerState<_TemplatesSheet> createState() => _TemplatesSheetState();
}

class _TemplatesSheetState extends ConsumerState<_TemplatesSheet> {
  final List<({TextEditingController head, TextEditingController body})> _rows = [];
  int _active = 0;
  bool _loading = true, _busy = false;

  @override
  void initState() {
    super.initState();
    ref
        .read(adminRepoProvider)
        .templates()
        .then((t) {
          if (!mounted) return;
          setState(() {
            for (var i = 0; i < t.length; i++) {
              _rows.add((head: TextEditingController(text: '${t[i]['heading']}'), body: TextEditingController(text: '${t[i]['text']}')));
              if (t[i]['active'] == true) _active = i;
            }
            _loading = false;
          });
        })
        .catchError((_) {
          if (mounted) setState(() => _loading = false);
        });
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await ref.read(adminRepoProvider).saveTemplates([
        for (var i = 0; i < _rows.length; i++) {'heading': _rows[i].head.text, 'text': _rows[i].body.text, 'active': i == _active},
      ]);
      if (mounted) {
        showMessage(context, 'Saved. Coordinators get the active message on their next refresh.');
        Navigator.pop(context);
      }
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SheetBody(
      children: [
        Text('WhatsApp messages', style: text.titleLarge),
        const SizedBox(height: 4),
        Text(
          'The selected message is sent by the Send Message button, after "Hare Krishna <name>". You can use {name} inside it.',
          style: text.bodyMedium,
        ),
        const SizedBox(height: 12),
        if (_loading) const Center(child: CircularProgressIndicator()),
        for (var i = 0; i < _rows.length; i++)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      RadioGroup<int>(
                        groupValue: _active,
                        onChanged: (v) => setState(() => _active = v ?? 0),
                        child: Radio<int>(value: i),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _rows[i].head,
                          decoration: const InputDecoration(labelText: 'Heading'),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Delete',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => setState(() {
                          _rows.removeAt(i);
                          if (_active >= _rows.length) _active = 0;
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _rows[i].body,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(labelText: 'Message'),
                  ),
                ],
              ),
            ),
          ),
        TextButton.icon(
          onPressed: () => setState(() => _rows.add((head: TextEditingController(text: 'Message'), body: TextEditingController()))),
          icon: const Icon(Icons.add),
          label: const Text('Add a message'),
        ),
        const SizedBox(height: 8),
        FilledButton(onPressed: _busy ? null : _save, child: Text(_busy ? 'Saving…' : 'Save')),
      ],
    );
  }
}
