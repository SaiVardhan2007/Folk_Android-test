import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_controller.dart';
import 'admin_repo.dart';
import '../../core/layout.dart';

final _callersProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) => ref.read(adminRepoProvider).callers());
final _statsProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, event) => ref.read(adminRepoProvider).callStats(event));

/// Admin → Calls: who is calling, assigning contacts to coordinators, follow-ups, message text and call statistics.
class CallsAdminTab extends ConsumerWidget {
  const CallsAdminTab({super.key});

  void _refresh(WidgetRef ref) {
    ref.invalidate(_callersProvider);
    ref.invalidate(_statsProvider);
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
    final event = ref.watch(selectedEventProvider);
    final boot = ref.watch(bootstrapProvider).value;
    final callers = ref.watch(_callersProvider);
    final repo = ref.read(adminRepoProvider);

    return PageBody(
      onRefresh: () async => _refresh(ref),
      children: [
        const EventPicker(label: 'Calls for event'),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.icon(
              onPressed: event == null
                  ? null
                  : () async {
                      final done = await showModalBottomSheet<bool>(
                        context: context,
                        isScrollControlled: true,
                        showDragHandle: true,
                        builder: (c) => _AssignSheet(event: event, boot: boot, callers: callers.value ?? const []),
                      );
                      if (done == true) _refresh(ref);
                    },
              icon: const Icon(Icons.assignment_ind_outlined),
              label: const Text('Assign contacts'),
            ),
            OutlinedButton.icon(
              onPressed: event == null
                  ? null
                  : () => _confirmRun(
                      context,
                      ref,
                      title: 'Hand out follow-ups?',
                      button: 'Hand out',
                      body:
                          'Contacts marked "Need to Call Again" or "Available on Weekend" go to coordinators with Auto assign on, as follow-up calls.',
                      run: () async {
                        final r = await repo.followUp(event, const []);
                        return '${r['moved']} follow-up call(s) handed out${(r['left'] as num) > 0 ? ', ${r['left']} had no coordinator with room' : ''}.';
                      },
                    ),
              icon: const Icon(Icons.replay_outlined),
              label: const Text('Follow-ups'),
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

class _AssignSheet extends ConsumerStatefulWidget {
  const _AssignSheet({required this.event, required this.boot, required this.callers});
  final String event;
  final Bootstrap? boot;
  final List<Map<String, dynamic>> callers;
  @override
  ConsumerState<_AssignSheet> createState() => _AssignSheetState();
}

class _AssignSheetState extends ConsumerState<_AssignSheet> {
  String _level = '', _gender = '', _attended = '', _reg = '';
  bool _reassign = false, _busy = false;
  late final Set<String> _picked = {
    for (final c in widget.callers)
      if (c['auto_assign'] == true) '${c['mob']}',
  };
  Map<String, dynamic>? _plan;

  Map<String, dynamic> get _body => {
    'event': widget.event,
    'level': _level,
    'gender': _gender,
    'attended': _attended,
    'reg_event': _reg,
    'coordinators': _picked.toList(),
    'reassign_unfinished': _reassign,
  };

  Future<void> _go({required bool preview}) async {
    setState(() => _busy = true);
    try {
      final r = await ref.read(adminRepoProvider).assign(_body, preview: preview);
      if (!mounted) return;
      if (preview) {
        setState(() => _plan = r);
      } else {
        showMessage(context, '${r['assignable']} contact(s) assigned.');
        Navigator.pop(context, true);
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
    final b = widget.boot;
    void changed(VoidCallback f) => setState(() {
      f();
      _plan = null;
    });
    return SheetBody(
      children: [
        Text('Assign contacts', style: text.titleLarge),
        const SizedBox(height: 4),
        Text(
          'Public contacts who match are shared between the chosen coordinators. Whoever has the fewest calls gets the next contact, and call limits are respected.',
          style: text.bodyMedium,
        ),
        const SizedBox(height: 14),
        FieldGrid(
          children: [
            OptionDropdown(
              label: 'Registered for event',
              value: _reg,
              options: [for (final e in b?.events ?? <FolkEvent>[]) e.code],
              labelOf: (c) => b!.events.firstWhere((e) => e.code == c).name,
              onChanged: (v) => changed(() => _reg = v),
            ),
            OptionDropdown(label: 'Level', value: _level, options: b?.levels ?? const [], onChanged: (v) => changed(() => _level = v)),
            OptionDropdown(
              label: 'Gender',
              value: _gender,
              options: const ['M', 'F'],
              labelOf: genderLabel,
              onChanged: (v) => changed(() => _gender = v),
            ),
            OptionDropdown(
              label: 'Attendance',
              value: _attended,
              options: const ['yes', 'no'],
              labelOf: (v) => v == 'yes' ? 'Has attended' : 'Never attended',
              onChanged: (v) => changed(() => _attended = v),
            ),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _reassign,
          onChanged: (v) => changed(() => _reassign = v),
          title: const Text('Also redistribute calls nobody has started'),
        ),
        Text('Coordinators', style: text.titleSmall),
        for (final c in widget.callers)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: _picked.contains('${c['mob']}'),
            onChanged: (v) => changed(() => v == true ? _picked.add('${c['mob']}') : _picked.remove('${c['mob']}')),
            title: Text('${c['name']}'),
            subtitle: Text('Has ${c['assigned']}${c['call_limit'] == null ? '' : '  •  limit ${c['call_limit']}'}'),
          ),
        if (_plan != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${_plan!['assignable']} of ${_plan!['pool']} matching contacts will be assigned', style: text.titleSmall),
                  if ((_plan!['already_assigned'] as num) > 0)
                    Text('${_plan!['already_assigned']} already assigned for this event', style: text.bodyMedium),
                  if ((_plan!['unassigned'] as num) > 0)
                    Text(
                      '${_plan!['unassigned']} will stay unassigned (call limits reached)',
                      style: text.bodyMedium?.copyWith(color: context.colors.warning),
                    ),
                  const SizedBox(height: 6),
                  for (final p in (_plan!['per_coordinator'] as List))
                    Text('${p['name']}: +${p['add']} (total ${p['total_after']})', style: text.bodyMedium),
                ],
              ),
            ),
          ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(onPressed: _busy ? null : () => _go(preview: true), child: const Text('Preview')),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: _busy || _plan == null || (_plan!['assignable'] as num) == 0 ? null : () => _go(preview: false),
                child: Text(_busy ? 'Working…' : 'Assign'),
              ),
            ),
          ],
        ),
      ],
    );
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
