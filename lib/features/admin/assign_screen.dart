import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/layout.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_controller.dart';
import 'admin_repo.dart';

typedef _Callers = ({List<Map<String, dynamic>> callers, List<String> statuses});
final _assignCallersProvider = FutureProvider.autoDispose.family<_Callers, String>((ref, event) => ref.read(adminRepoProvider).callers(event: event));

/// How many contacts go to the server in one write. Small, so each one finishes quickly and a failure only repeats a few.
const _kBatch = 50;

/// Admin → Calls → Assign. One place for every hand-out:
///  1. choose what to assign (new contacts, contacts from other coordinators, follow-ups by call status),
///  2. choose who receives them and how (same coordinator as before, or random and equal),
///  3. Preview shows exactly what will happen, then Assign writes it in small repeatable batches with a progress bar.
class AssignScreen extends ConsumerStatefulWidget {
  const AssignScreen({super.key, required this.event, required this.eventName});
  final String event, eventName;
  @override
  ConsumerState<AssignScreen> createState() => _AssignScreenState();
}

class _AssignScreenState extends ConsumerState<AssignScreen> {
  String _scope = 'new'; // new | others | followup
  String _mode = 'random'; // random | previous
  String _level = '', _gender = '', _attended = '', _reg = '';
  final Set<String> _statuses = {}, _from = {}, _to = {};
  bool _toReady = false;
  DateTime? _dateFrom, _dateTo;
  final _limit = TextEditingController();

  Map<String, dynamic>? _plan;
  bool _planning = false, _running = false;
  String? _error;
  int _done = 0, _skipped = 0, _total = 0;
  final Set<int> _finished = {};
  List<Map<String, dynamic>> _batches = const [];

  @override
  void dispose() {
    _limit.dispose();
    super.dispose();
  }

  static String _day(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> get _body => {
    'event': widget.event,
    'scope': _scope,
    'mode': _scope == 'others' ? 'random' : _mode,
    'coordinators': _to.toList(),
    if (_scope == 'new') ...{'level': _level, 'gender': _gender, 'attended': _attended, 'reg_event': _reg},
    if (_scope != 'new') 'from': _from.toList(),
    if (_scope == 'followup') ...{
      'statuses': _statuses.toList(),
      if (_dateFrom != null) 'date_from': _day(_dateFrom!),
      if (_dateTo != null) 'date_to': _day(_dateTo!),
    },
    if (_limit.text.trim().isNotEmpty) 'limit': int.tryParse(_limit.text.trim()),
  };

  /// Any change to the choices invalidates the preview, so what is applied is always what was previewed.
  void _changed(VoidCallback f) {
    if (_running) return;
    setState(() {
      f();
      _plan = null;
      _error = null;
    });
  }

  Future<void> _preview() async {
    setState(() {
      _planning = true;
      _error = null;
    });
    try {
      final r = await ref.read(adminRepoProvider).planAssign(_body);
      if (!mounted) return;
      setState(() {
        _plan = r;
        _finished.clear();
        _done = 0;
        _skipped = 0;
        _batches = _makeBatches(r);
        _total = _batches.fold(0, (t, b) => t + (b['persons'] as List).length);
      });
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _planning = false);
    }
  }

  List<Map<String, dynamic>> _makeBatches(Map<String, dynamic> plan) {
    final out = <Map<String, dynamic>>[];
    for (final m in (plan['moves'] as List)) {
      final persons = [for (final p in (m['persons'] as List)) '$p'];
      for (var i = 0; i < persons.length; i += _kBatch) {
        out.add({'coordinator': m['coordinator'], 'persons': persons.sublist(i, i + _kBatch > persons.length ? persons.length : i + _kBatch)});
      }
    }
    return out;
  }

  /// Applies every batch that is not finished yet. Safe to run again after a failure: it carries on where it stopped.
  Future<void> _apply() async {
    final plan = _plan;
    if (plan == null || _running) return;
    setState(() {
      _running = true;
      _error = null;
    });
    final repo = ref.read(adminRepoProvider);
    final todo = [
      for (var i = 0; i < _batches.length; i++)
        if (!_finished.contains(i)) i,
    ];
    var next = 0;
    Object? failure;

    Future<void> worker() async {
      while (failure == null && next < todo.length) {
        final i = todo[next++];
        final b = _batches[i];
        final r = await _sendWithRetry(repo, {
          'event': widget.event,
          'follow_up': plan['follow_up'],
          'allow': plan['allow'],
          'moves': [b],
        });
        if (!mounted) return;
        setState(() {
          _finished.add(i);
          _done += (b['persons'] as List).length;
          _skipped += (r['skipped'] as num?)?.toInt() ?? 0;
        });
      }
    }

    // Three at a time: different contacts, so they never touch the same record.
    await Future.wait([
      for (var w = 0; w < 3; w++)
        worker().catchError((Object e) {
          failure ??= e;
        }),
    ]);
    if (!mounted) return;
    if (failure != null) {
      final f = failure;
      setState(() {
        _running = false;
        _error = f is ApiException ? f.message : 'Something went wrong.';
      });
      return;
    }
    unawaited(repo.finishAssign({'event': widget.event, 'scope': _scope, 'assigned': _done - _skipped}).catchError((_) {}));
    final msg = '${_done - _skipped} contact(s) assigned.${_skipped > 0 ? ' $_skipped skipped (already called or changed meanwhile).' : ''}';
    showMessage(context, msg);
    Navigator.pop(context, true);
  }

  /// One batch, tried up to 3 times when the connection drops or the server is busy. Repeating a batch is harmless.
  Future<Map<String, dynamic>> _sendWithRetry(AdminRepo repo, Map<String, dynamic> body) async {
    for (var attempt = 1; ; attempt++) {
      try {
        return await repo.applyAssign(body);
      } on ApiException catch (e) {
        final retryable = e.isNetwork || (e.status ?? 0) >= 500;
        if (!retryable || attempt >= 3) rethrow;
        await Future<void>.delayed(Duration(seconds: attempt * 2));
      }
    }
  }

  Future<void> _pickDate(bool from) async {
    final now = DateTime.now();
    final d = await showDatePicker(context: context, initialDate: (from ? _dateFrom : _dateTo) ?? now, firstDate: DateTime(2024), lastDate: now);
    if (d != null) _changed(() => from ? _dateFrom = d : _dateTo = d);
  }

  @override
  Widget build(BuildContext context) {
    final callersAsync = ref.watch(_assignCallersProvider(widget.event));
    return PopScope(
      canPop: !_running,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) showMessage(context, 'Please wait: still assigning. Keep this screen open until it finishes.');
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Assign calls')),
        body: callersAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorView(
            message: e is ApiException ? e.message : 'Could not load coordinators.',
            onRetry: () => ref.invalidate(_assignCallersProvider(widget.event)),
          ),
          data: (data) {
            if (!_toReady) {
              _toReady = true;
              _to.addAll([
                for (final c in data.callers)
                  if (c['auto_assign'] == true) '${c['mob']}',
              ]);
            }
            return _form(context, data);
          },
        ),
        bottomNavigationBar: callersAsync.hasValue ? _actions(context) : null,
      ),
    );
  }

  Widget _form(BuildContext context, _Callers data) {
    final text = Theme.of(context).textTheme;
    final boot = ref.watch(bootstrapProvider).value;
    final callers = data.callers;
    String count(Map<String, dynamic> c) =>
        'Pending ${c['pending']}  •  Total ${c['assigned']}${c['call_limit'] == null ? '' : '  •  Limit ${c['call_limit']}'}';

    Widget step(String n, String title, List<Widget> children) => Card(
      margin: const EdgeInsets.only(bottom: kGapM),
      child: Padding(
        padding: const EdgeInsets.all(kGapL),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$n  $title', style: text.titleMedium),
            const SizedBox(height: kGapM),
            ...children,
          ],
        ),
      ),
    );

    final scopeHelp = switch (_scope) {
      'new' => 'Contacts nobody has been assigned to yet for ${widget.eventName}. Use this when new contacts have come in.',
      'others' =>
        'Takes contacts that have not been called yet away from other coordinators and gives them to the ones you pick below. Use this when a new coordinator joins.',
      _ => 'Contacts whose last call had the status you choose go to a coordinator for another try. Their old call history is kept.',
    };

    return AbsorbPointer(
      absorbing: _running,
      child: PageBody(
        children: [
          Text(widget.eventName, style: text.titleLarge),
          const SizedBox(height: kGapS),
          step('1', 'What do you want to assign?', [
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'new', label: Text('New contacts')),
                ButtonSegment(value: 'others', label: Text('From others')),
                ButtonSegment(value: 'followup', label: Text('Follow-ups')),
              ],
              selected: {_scope},
              onSelectionChanged: (v) => _changed(() => _scope = v.first),
            ),
            const SizedBox(height: kGapM),
            Text(scopeHelp, style: text.bodyMedium),
          ]),
          step('2', 'Which contacts?', [
            if (_scope == 'new')
              FieldGrid(
                children: [
                  OptionDropdown(
                    label: 'Registered for event',
                    value: _reg,
                    options: [for (final e in boot?.eventsAndLists ?? <FolkEvent>[]) e.code],
                    labelOf: (c) => boot!.eventsAndLists.firstWhere((e) => e.code == c).name,
                    onChanged: (v) => _changed(() => _reg = v),
                  ),
                  OptionDropdown(label: 'Level', value: _level, options: boot?.levels ?? const [], onChanged: (v) => _changed(() => _level = v)),
                  OptionDropdown(
                    label: 'Gender',
                    value: _gender,
                    options: const ['M', 'F'],
                    labelOf: genderLabel,
                    onChanged: (v) => _changed(() => _gender = v),
                  ),
                  OptionDropdown(
                    label: 'Attendance',
                    value: _attended,
                    options: const ['yes', 'no'],
                    labelOf: (v) => v == 'yes' ? 'Has attended' : 'Never attended',
                    onChanged: (v) => _changed(() => _attended = v),
                  ),
                ],
              ),
            if (_scope == 'followup') ...[
              Text('Call status (pick one or more)', style: text.titleSmall),
              const SizedBox(height: kGapS),
              Wrap(
                spacing: kGapS,
                runSpacing: kGapXS,
                children: [
                  for (final s in data.statuses)
                    FilterChip(
                      label: Text(s),
                      selected: _statuses.contains(s),
                      onSelected: (v) => _changed(() => v ? _statuses.add(s) : _statuses.remove(s)),
                    ),
                ],
              ),
              const SizedBox(height: kGapM),
              Text('Called between (optional)', style: text.titleSmall),
              const SizedBox(height: kGapS),
              Row(
                children: [
                  Expanded(child: _dateButton('From date', _dateFrom, () => _pickDate(true), () => _changed(() => _dateFrom = null))),
                  const SizedBox(width: kGapS),
                  Expanded(child: _dateButton('To date', _dateTo, () => _pickDate(false), () => _changed(() => _dateTo = null))),
                ],
              ),
            ],
            if (_scope != 'new') ...[
              if (_scope == 'followup') const SizedBox(height: kGapM),
              Text(
                _scope == 'others' ? 'Take from (leave empty for all other coordinators)' : 'Only calls made by (leave empty for everyone)',
                style: text.titleSmall,
              ),
              const SizedBox(height: kGapS),
              Wrap(
                spacing: kGapS,
                runSpacing: kGapXS,
                children: [
                  for (final c in callers)
                    FilterChip(
                      label: Text('${c['name']}${_scope == 'others' ? ' (${c['pending']})' : ''}'),
                      selected: _from.contains('${c['mob']}'),
                      onSelected: (v) => _changed(() => v ? _from.add('${c['mob']}') : _from.remove('${c['mob']}')),
                    ),
                ],
              ),
            ],
            const SizedBox(height: kGapM),
            TextField(
              controller: _limit,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
              onChanged: (_) => _changed(() {}),
              decoration: InputDecoration(
                labelText: 'How many at most (optional)',
                helperText: _scope == 'others'
                    ? 'For example 100: takes them fairly from whoever has the most.'
                    : 'Leave empty for all matching contacts.',
              ),
            ),
          ]),
          step('3', 'Who should get them?', [
            Row(
              children: [
                TextButton(onPressed: () => _changed(() => _to.addAll([for (final c in callers) '${c['mob']}'])), child: const Text('Select all')),
                TextButton(onPressed: () => _changed(_to.clear), child: const Text('Clear')),
              ],
            ),
            if (callers.isEmpty) Text('No active coordinators yet.', style: text.bodyMedium),
            for (final c in callers)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _to.contains('${c['mob']}'),
                onChanged: (v) => _changed(() => v == true ? _to.add('${c['mob']}') : _to.remove('${c['mob']}')),
                title: Text('${c['name']}'),
                subtitle: Text(count(c)),
              ),
          ]),
          if (_scope != 'others')
            step('4', 'How should they be shared?', [
              RadioGroup<String>(
                groupValue: _mode,
                onChanged: (v) => _changed(() => _mode = v ?? 'random'),
                child: Column(
                  children: [
                    RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      value: 'random',
                      title: const Text('Random, shared equally'),
                      subtitle: const Text('Contacts are shuffled and shared so every chosen coordinator ends up with about the same number.'),
                    ),
                    RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      value: 'previous',
                      title: Text(_scope == 'followup' ? 'Same coordinator who called them' : 'Same coordinator as before'),
                      subtitle: Text(
                        _scope == 'followup'
                            ? 'Each contact goes back to the coordinator who made the last call, if they are chosen above.'
                            : 'Each contact goes back to the coordinator who had them in an earlier event or call, if they are chosen above. Everyone else is shared equally.',
                      ),
                    ),
                  ],
                ),
              ),
            ]),
          if (_plan != null) _planCard(context),
          if (_error != null)
            StatusBanner(
              icon: Icons.error_outline,
              color: context.colors.danger,
              text: '$_error  Nothing is lost: tap Resume to carry on from where it stopped.',
            ),
        ],
      ),
    );
  }

  Widget _dateButton(String label, DateTime? d, VoidCallback pick, VoidCallback clear) => Row(
    children: [
      Expanded(
        child: OutlinedButton.icon(
          onPressed: pick,
          icon: const Icon(Icons.calendar_today_outlined, size: 18),
          label: Text(d == null ? label : _day(d), overflow: TextOverflow.ellipsis),
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52)),
        ),
      ),
      if (d != null) IconButton(tooltip: 'Clear', icon: const Icon(Icons.close), onPressed: clear),
    ],
  );

  Widget _planCard(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = _plan!;
    int n(String k) => (p[k] as num?)?.toInt() ?? 0;
    final taken = [for (final t in (p['taken_from'] as List? ?? const [])) Map<String, dynamic>.from(t as Map)];
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.all(kGapL),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(n('assignable') == 0 ? 'Nothing to assign' : '${n('assignable')} contact(s) will be assigned', style: text.titleMedium),
            if (n('candidates') > n('assignable') + n('unassigned'))
              Text('${n('candidates')} matched, limited to ${n('assignable') + n('unassigned')}.', style: text.bodyMedium),
            if (_mode == 'previous' && _scope != 'others' && n('assignable') > 0) ...[
              Text('${n('kept_with_previous')} go back to the same coordinator', style: text.bodyMedium),
              Text('${n('shared_out')} are shared equally', style: text.bodyMedium),
            ],
            if (n('unassigned') > 0)
              Text('${n('unassigned')} will stay as they are (call limits reached)', style: text.bodyMedium?.copyWith(color: context.colors.warning)),
            if (taken.isNotEmpty) ...[
              const SizedBox(height: kGapS),
              Text('Taken from', style: text.titleSmall),
              for (final t in taken) Text('${t['name']}: ${t['count']}', style: text.bodyMedium),
            ],
            const SizedBox(height: kGapS),
            Text('Given to', style: text.titleSmall),
            for (final c in (p['per_coordinator'] as List)) Text('${c['name']}: +${c['add']}  (total ${c['total_after']})', style: text.bodyMedium),
            if (n('assignable') == 0 && n('unassigned') == 0) ...[
              const SizedBox(height: kGapS),
              Text('No contacts match these choices.', style: text.bodyMedium),
            ],
          ],
        ),
      ),
    );
  }

  Widget _actions(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final assignable = (_plan?['assignable'] as num?)?.toInt() ?? 0;
    final canPreview = !_running && !_planning && _to.isNotEmpty && (_scope != 'followup' || _statuses.isNotEmpty);
    final resume = _error != null && _plan != null;
    return Material(
      elevation: 8,
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(kPagePadding, kGapM, kPagePadding, kGapM),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_running || resume) ...[
                LinearProgressIndicator(value: _total == 0 ? null : _done / _total, minHeight: 8),
                const SizedBox(height: kGapS),
                Text('${_running ? 'Assigning' : 'Stopped at'} $_done of $_total', style: text.bodyMedium),
                const SizedBox(height: kGapS),
              ],
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(onPressed: canPreview ? _preview : null, child: Text(_planning ? 'Checking…' : 'Preview')),
                  ),
                  const SizedBox(width: kGapM),
                  Expanded(
                    child: FilledButton(
                      onPressed: _running || _plan == null || assignable == 0 ? null : _apply,
                      child: Text(_running ? 'Working…' : (resume ? 'Resume' : 'Assign now')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
