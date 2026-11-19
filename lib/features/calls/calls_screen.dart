import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'calls_repo.dart';
import '../../core/layout.dart';

/// "My Calls": the contacts an admin assigned to me. I call them from here, pick the outcome and submit.
class CallsScreen extends ConsumerStatefulWidget {
  const CallsScreen({super.key});
  @override
  ConsumerState<CallsScreen> createState() => _CallsScreenState();
}

class _CallsScreenState extends ConsumerState<CallsScreen> {
  final _search = TextEditingController();
  bool _showFollowUp = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(CallItem i) {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return true;
    final digits = q.replaceAll(RegExp(r'\D'), '');
    return i.name.toLowerCase().contains(q) || (digits.isNotEmpty && i.mob.contains(digits));
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(callsProvider);
    final text = Theme.of(context).textTheme;
    return PageBody(
      onRefresh: () async => ref.refresh(callsProvider.future),
      children: [
        data.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(48),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) =>
              ErrorView(message: e is ApiException ? e.message : 'Could not load your calls.', onRetry: () => ref.invalidate(callsProvider)),
          data: (d) {
            final events = d.items.map((i) => i.eventName).where((e) => e.isNotEmpty).toSet(); // one event: shown once at the top, not on every card
            final main = d.items.where((i) => !i.isFollowUp).toList();
            final follow = d.items.where((i) => i.isFollowUp).toList();
            final pending = main.where((i) => i.isPending).length;
            final positive = main.where((i) => d.positive.contains(i.status)).length;
            final done = main.isEmpty ? 0 : ((main.length - pending) * 100 / main.length).round();
            final showFollow = follow.isNotEmpty && (_showFollowUp || pending == 0);
            List<CallItem> order(List<CallItem> l) => [...l.where((i) => i.isPending), ...l.where((i) => !i.isPending)].where(_matches).toList();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(events.length == 1 ? events.first : 'Your calls', style: text.titleMedium, overflow: TextOverflow.ellipsis),
                    ),
                    Chip(label: Text('$done% completed'), visualDensity: VisualDensity.compact),
                  ],
                ),
                const SizedBox(height: kGapS),
                StatStrip(
                  children: [
                    MiniStat(label: 'Total', value: main.length, color: context.colors.brand),
                    MiniStat(label: 'Positive', value: positive, color: context.colors.success),
                    MiniStat(label: 'Pending', value: pending, color: context.colors.warning),
                    MiniStat(
                      label: 'Follow-up',
                      value: follow.length,
                      color: context.colors.danger,
                      onTap: follow.isEmpty ? null : () => setState(() => _showFollowUp = !_showFollowUp),
                    ),
                  ],
                ),
                const SizedBox(height: kGapM),
                TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Search name or number',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _search.text.isEmpty ? null : IconButton(icon: const Icon(Icons.close), onPressed: () => setState(_search.clear)),
                  ),
                ),
                const SizedBox(height: 8),
                if (d.items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Text(
                        'No calls assigned to you yet.\nYou will get a notification when an admin assigns some.',
                        textAlign: TextAlign.center,
                        style: text.bodyLarge,
                      ),
                    ),
                  ),
                for (final i in order(main))
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: _CallCard(key: ValueKey(i.id), item: i, data: d, showEvent: events.length > 1),
                  ),
                if (showFollow) ...[
                  SectionTitle('Follow-up calls (${follow.length})'),
                  for (final i in order(follow))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _CallCard(key: ValueKey(i.id), item: i, data: d, showEvent: events.length > 1),
                    ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _CallCard extends ConsumerStatefulWidget {
  const _CallCard({super.key, required this.item, required this.data, this.showEvent = false});
  final bool showEvent;
  final CallItem item;
  final CallsData data;
  @override
  ConsumerState<_CallCard> createState() => _CallCardState();
}

class _CallCardState extends ConsumerState<_CallCard> {
  late String _status = widget.item.isPending ? '' : widget.item.status;
  late String _note = widget.item.note;
  bool _called = false, _messaged = false, _busy = false;
  String _ref = CallsRepo.newRef();

  @override
  void initState() {
    super.initState();
    if (widget.item.isPending) _restore();
  }

  /// Picks up where the coordinator left off (they called, then left this screen or the app before submitting).
  Future<void> _restore() async {
    final dr = await CallDraft.load(item.id);
    if (dr == null || !mounted) return;
    setState(() {
      _called = dr.called;
      _messaged = dr.messaged;
      if (_status.isEmpty && d.statuses.contains(dr.status)) _status = dr.status;
      if (_note.isEmpty) _note = dr.note;
    });
  }

  void _remember() => CallDraft(called: _called, messaged: _messaged, status: _status, note: _note).save(item.id);

  CallItem get item => widget.item;
  CallsData get d => widget.data;
  bool get _first => item.isPending;
  bool get _isPositive => d.positive.contains(_status);
  bool get _unchanged => !_first && _status == item.status && _note == item.note;

  String get _buttonLabel {
    if (_busy) return 'Saving…';
    if (_status.isEmpty) return 'Choose a status';
    if (_unchanged) return '✓ Submitted';
    if (_first && !_called) return 'Call first';
    if (_first && _isPositive && !_messaged) return 'Send message first';
    return 'Submit';
  }

  bool get _canSubmit => !_busy && _status.isNotEmpty && !_unchanged && !(_first && !_called) && !(_first && _isPositive && !_messaged);

  Future<void> _call() async {
    setState(() => _called = true);
    _remember(); // kept even if they leave this screen or the app while on the call
    final ok = await FlutterPhoneDirectCaller.callNumber('+91${item.mob}');
    if (ok != true) await launchUrl(Uri.parse('tel:+91${item.mob}'));
  }

  Future<void> _whatsapp() async {
    final extra = d.messageText.replaceAll('{name}', item.name);
    final msg = 'Hare Krishna ${item.name}${extra.isEmpty ? '' : '\n\n$extra'}';
    final ok = await launchUrl(Uri.parse('https://wa.me/91${item.mob}?text=${Uri.encodeComponent(msg)}'), mode: LaunchMode.externalApplication);
    if (ok) {
      setState(() => _messaged = true);
      _remember();
    } else if (mounted) {
      showMessage(context, 'Could not open WhatsApp.', error: true);
    }
  }

  /// Asks for a note. Required for some statuses (Cancel then undoes the status). Otherwise Cancel just means "no note" and the status stays.
  Future<String?> _askNote(String status, {required bool required}) {
    final c = TextEditingController(text: _note);
    return showDialog<String>(
      context: context,
      barrierDismissible: !required,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(required ? 'Note needed' : 'Add a note?'),
          content: TextField(
            controller: c,
            autofocus: true,
            maxLines: 4,
            onChanged: (_) => set(() {}),
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(hintText: required ? 'Write what happened (required for "$status")' : 'Optional'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(100, 48)),
              onPressed: required && c.text.trim().isEmpty ? null : () => Navigator.pop(ctx, c.text.trim()),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pick(String v) async {
    final required = d.noteRequired.contains(v);
    final prev = _status;
    setState(() => _status = v);
    final n = await _askNote(v, required: required);
    if (!mounted) return;
    if (n != null) {
      setState(() => _note = n);
    } else if (required) {
      setState(() => _status = prev); // cancelled a required note: undo the choice
    }
    _remember();
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      await ref.read(callsRepoProvider).submit(item.id, status: _status, note: _note, ref: _ref);
      HapticFeedback.mediumImpact();
      if (mounted) showMessage(context, 'Thanks for submitting 🙏');
      _ref = CallsRepo.newRef();
      await CallDraft.clear(item.id);
      ref.invalidate(callsProvider);
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.isNetwork ? 'No internet. Tap Submit again when you are back online.' : e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _history(bool calls) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => _HistorySheet(mob: item.mob, name: item.name, calls: calls),
  );

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final statuses = d.statuses.where((s) => s != 'Not Done').toList();
    final submitted = !item.isPending;
    return Card(
      color: submitted ? Theme.of(context).colorScheme.surfaceContainerLow : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(item.name.isEmpty ? 'No name' : item.name, style: text.titleMedium)),
                if (submitted) Icon(Icons.check_circle, color: context.colors.success),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (widget.showEvent) Chip(avatar: const Icon(Icons.event_outlined, size: 18), label: Text(item.eventName)),
                ActionChip(
                  avatar: const Icon(Icons.fact_check_outlined, size: 18),
                  label: Text('Sessions: ${item.sessions}'),
                  onPressed: () => _history(false),
                ),
                ActionChip(
                  avatar: const Icon(Icons.phone_in_talk_outlined, size: 18),
                  label: Text('Last 4 weeks: ${item.calls28d}'),
                  onPressed: () => _history(true),
                ),
                if (item.level.isNotEmpty) Chip(label: Text(item.level)),
              ],
            ),
            if (item.profession.isNotEmpty || item.pgName.isNotEmpty || item.venue.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text([item.profession, item.pgName, item.venue].where((s) => s.isNotEmpty).join('  •  '), style: text.bodyMedium),
              ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _call,
              icon: const Icon(Icons.call),
              label: Text('Call  ${item.mob.length == 10 ? '${item.mob.substring(0, 5)} ${item.mob.substring(5)}' : item.mob}'),
              style: FilledButton.styleFrom(backgroundColor: _called ? context.colors.success : null),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey('st-${item.id}-$_status'),
              initialValue: statuses.contains(_status) ? _status : null,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Call status', prefixIcon: Icon(Icons.flag_outlined)),
              items: [
                for (final s in statuses)
                  DropdownMenuItem(
                    value: s,
                    child: Text(s, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) => v == null ? null : _pick(v),
            ),
            if (_note.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    const Icon(Icons.sticky_note_2_outlined, size: 20),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_note, style: text.bodyMedium)),
                    IconButton(
                      tooltip: 'Edit note',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: _status.isEmpty
                          ? null
                          : () async {
                              final n = await _askNote(_status, required: d.noteRequired.contains(_status));
                              if (n != null && mounted) {
                                setState(() => _note = n);
                                _remember();
                              }
                            },
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            // Stacked full-width buttons: long labels such as "Send message first" never wrap on a phone.
            OutlinedButton.icon(
              onPressed: _whatsapp,
              icon: Icon(_messaged ? Icons.mark_chat_read_outlined : Icons.chat_outlined),
              label: const Text('WhatsApp'),
            ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: _canSubmit ? _submit : null,
              style: FilledButton.styleFrom(backgroundColor: context.colors.success),
              child: Text(_buttonLabel, textAlign: TextAlign.center),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistorySheet extends ConsumerWidget {
  const _HistorySheet({required this.mob, required this.name, required this.calls});
  final String mob, name;
  final bool calls;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    return FutureBuilder<Map<String, dynamic>>(
      future: ref.read(callsRepoProvider).history(mob),
      builder: (context, snap) {
        Widget body;
        if (snap.connectionState != ConnectionState.done) {
          body = const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          );
        } else if (snap.hasError) {
          body = const ErrorView(message: 'Could not load the history.');
        } else {
          final rows = ((snap.data![calls ? 'calls' : 'sessions'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
          body = rows.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(child: Text(calls ? 'No calls recorded yet.' : 'No sessions attended yet.', style: text.bodyLarge)),
                )
              : Column(
                  children: [
                    for (final r in rows)
                      ListTile(
                        leading: Icon(calls ? Icons.phone_in_talk_outlined : Icons.check_circle_outline),
                        title: Text(calls ? '${r['status']}' : '${r['event_code']}'),
                        subtitle: Text(
                          [
                            '${r[calls ? 'called_at' : 'ts']}',
                            if (calls && '${r['coordinator_name'] ?? ''}'.isNotEmpty) 'by ${r['coordinator_name']}',
                            if (!calls && '${r['marked_by_name'] ?? ''}'.isNotEmpty) 'marked by ${r['marked_by_name']}',
                            if (calls && '${r['note'] ?? ''}'.isNotEmpty) '“${r['note']}”',
                          ].join('\n'),
                        ),
                        isThreeLine: calls && '${r['note'] ?? ''}'.isNotEmpty,
                      ),
                  ],
                );
        }
        return SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(kPagePadding, 0, kPagePadding, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${calls ? 'Calls' : 'Sessions'}: $name', style: text.titleLarge),
                  const SizedBox(height: 8),
                  body,
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
