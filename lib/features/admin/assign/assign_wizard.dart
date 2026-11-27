import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api.dart';
import '../../../core/layout.dart';
import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../admin_repo.dart';
import 'assign_models.dart';
import 'assign_widgets.dart';

typedef _Callers = ({List<Map<String, dynamic>> callers, List<String> statuses});
final _callersProvider = FutureProvider.autoDispose.family<_Callers, String>((ref, event) => ref.read(adminRepoProvider).callers(event: event));

/// Admin → Calls → Assign calls. A step-by-step wizard: one question per screen, a Review before anything is saved,
/// then the plan is written in small repeatable batches. There is no way to jump around in the middle.
class AssignWizard extends ConsumerStatefulWidget {
  const AssignWizard({super.key, required this.event, required this.eventName, this.reassignUnstarted = false, this.moveFromMob});
  final String event, eventName;

  /// "Reassign Unstarted": skips the start screen and moves every call nobody has made to the coordinators picked.
  final bool reassignUnstarted;

  /// Opens "Move a coordinator's calls" with this coordinator already ticked (used when switching a coordinator off).
  final String? moveFromMob;
  @override
  ConsumerState<AssignWizard> createState() => _AssignWizardState();
}

enum _Phase { edit, saving, done }

class _AssignWizardState extends ConsumerState<AssignWizard> {
  late final AssignDraft _d = AssignDraft(widget.event)
    ..kind = widget.reassignUnstarted || widget.moveFromMob != null ? AssignKind.move : null
    ..all = widget.reassignUnstarted;
  late int _i = widget.moveFromMob == null ? 0 : 1;
  _Phase _phase = _Phase.edit;

  Map<String, dynamic>? _plan;
  bool _planning = false;
  String? _planError, _saveError;
  List<Map<String, dynamic>> _batches = const [];
  final Set<int> _finished = {};
  Timer? _planTimer;
  int _done = 0, _skipped = 0, _total = 0;
  final Map<String, int> _added = {}; // contacts added per coordinator, sent once at the end so each coordinator gets one notification

  List<AssignStep> get _steps => stepsFor(_d.kind, reassign: widget.reassignUnstarted);
  AssignStep get _step => _steps[_i];
  bool get _busy => _phase == _Phase.saving;

  @override
  void initState() {
    super.initState();
    final m = widget.moveFromMob;
    if (m != null) _d.from.add(m);
  }

  @override
  void dispose() {
    _planTimer?.cancel();
    super.dispose();
  }

  /// 1 when the first step is the start screen (not counted as a step).
  int get _first => _steps.first == AssignStep.start ? 1 : 0;

  void _go(int to) {
    setState(() {
      _i = to;
      _plan = null;
      _planError = null;
    });
    if (_step == AssignStep.coordinators) _makePlan();
  }

  /// Any change to the choices invalidates the plan, so what is saved is always what was shown. The new plan is asked for
  /// shortly after the last change, never once per keystroke.
  void _touch() {
    setState(() {
      _plan = null;
      _planError = null;
    });
    if (_step != AssignStep.coordinators) return;
    _planTimer?.cancel();
    if (_d.coords.isEmpty) return;
    _planTimer = Timer(const Duration(milliseconds: 400), _makePlan);
  }

  Future<void> _makePlan() async {
    if (_d.coords.isEmpty) return;
    setState(() => _planning = true);
    try {
      final r = await ref.read(adminRepoProvider).planAssign(_d.planBody());
      if (!mounted) return;
      setState(() {
        _plan = r;
        _batches = makeBatches(r);
        _finished.clear();
        _done = _skipped = 0;
        _added.clear();
        _total = _batches.fold(0, (t, b) => t + (b['persons'] as List).length);
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _planError = e.message);
    } finally {
      if (mounted) setState(() => _planning = false);
    }
  }

  Future<Map<String, dynamic>> _retry(Future<Map<String, dynamic>> Function() f) async {
    for (var attempt = 1; ; attempt++) {
      try {
        return await f();
      } on ApiException catch (e) {
        if (!(e.isNetwork || (e.status ?? 0) >= 500) || attempt >= 3) rethrow;
        await Future<void>.delayed(Duration(seconds: attempt * 2));
      }
    }
  }

  /// Writes every batch that is not finished yet. Safe to run again after a failure.
  Future<void> _save() async {
    final plan = _plan;
    if (plan == null || _busy) return;
    setState(() {
      _phase = _Phase.saving;
      _saveError = null;
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
        final r = await _retry(
          () => repo.applyAssign({
            'event': widget.event,
            'follow_up': plan['follow_up'],
            'allow': plan['allow'],
            'moves': [b],
          }),
        );
        if (!mounted) return;
        setState(() {
          _finished.add(i);
          _done += (b['persons'] as List).length;
          _skipped += (r['skipped'] as num?)?.toInt() ?? 0;
          ((r['added'] as Map?) ?? const {}).forEach((k, v) => _added['$k'] = (_added['$k'] ?? 0) + ((v as num?)?.toInt() ?? 0));
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
        _phase = _Phase.edit;
        _saveError = f is ApiException ? f.message : 'Something went wrong.';
      });
      return;
    }
    unawaited(repo.finishAssign({'event': widget.event, 'scope': _d.kind!.name, 'assigned': _done - _skipped, 'counts': _added}).catchError((_) {}));
    setState(() => _phase = _Phase.done);
  }

  Future<bool> _confirmLeave() async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Leave without saving?'),
          content: const Text('Nothing has been assigned yet. Your choices will be lost.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Stay')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Leave')),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_callersProvider(widget.event));
    final unsaved = _phase == _Phase.edit && _d.kind != null;
    return PopScope(
      canPop: !_busy && !unsaved,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (_busy) {
          showMessage(context, 'Please wait: still assigning. Keep this screen open until it finishes.');
        } else if (await _confirmLeave() && context.mounted) {
          Navigator.pop(context, false);
        }
      },
      child: Scaffold(
        appBar: AppBar(title: Text(widget.reassignUnstarted ? 'Reassign Unstarted' : 'Assign calls'), automaticallyImplyLeading: !_busy),
        body: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorView(
            message: e is ApiException ? e.message : 'Could not load coordinators.',
            onRetry: () => ref.invalidate(_callersProvider(widget.event)),
          ),
          data: (data) => _phase == _Phase.edit ? _page(context, data) : _saving(context),
        ),
        bottomNavigationBar: async.hasValue ? _bar(context, async.requireValue) : null,
      ),
    );
  }

  // ---------- screens

  Widget _page(BuildContext context, _Callers data) {
    final text = Theme.of(context).textTheme;
    return PageBody(
      children: [
        if (_step != AssignStep.start && _steps.length > 1) ...[
          Text('Step ${_i + 1 - _first} of ${_steps.length - _first}', style: text.bodyMedium),
          const SizedBox(height: kGapXS),
          LinearProgressIndicator(value: (_i + 1 - _first) / (_steps.length - _first), minHeight: 6),
          const SizedBox(height: kGapL),
        ],
        switch (_step) {
          AssignStep.start => _start(context, data),
          AssignStep.who => _who(),
          AssignStep.calls => _calls(context, data),
          AssignStep.from => _from(data),
          AssignStep.coordinators => _coordinators(context, data),
        },
        if (_saveError != null) ...[
          const SizedBox(height: kGapM),
          StatusBanner(
            icon: Icons.error_outline,
            color: context.colors.danger,
            text: '$_saveError  Nothing is lost: tap Resume to carry on from where it stopped.',
          ),
        ],
      ],
    );
  }

  Widget _start(BuildContext context, _Callers data) {
    final text = Theme.of(context).textTheme;
    final assigned = data.callers.fold<int>(0, (t, c) => t + ((c['assigned'] as num?)?.toInt() ?? 0));
    final waiting = data.callers.fold<int>(0, (t, c) => t + ((c['pending'] as num?)?.toInt() ?? 0));
    Widget card(AssignKind k, IconData icon, String title) => Card(
      child: ListTile(
        contentPadding: const EdgeInsets.all(kGapL),
        leading: Icon(icon, size: 32),
        title: Text(title, style: text.titleMedium),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          _d.kind = k;
          _go(1);
        },
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StepHeader(title: widget.eventName, help: '$assigned assigned  •  $waiting waiting for a first call'),
        card(AssignKind.assign, Icons.people_alt_outlined, 'Assign calls'),
        card(AssignKind.followup, Icons.replay, 'Follow-up calls'),
        card(AssignKind.move, Icons.swap_horiz, "Move a coordinator's calls"),
      ],
    );
  }

  Widget _who() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const StepHeader(title: 'Who should be called?'),
      FilterEditor(filters: _d.filters, poolBody: _d.poolBody(), onChanged: _touch),
    ],
  );

  Widget _calls(BuildContext context, _Callers data) {
    final text = Theme.of(context).textTheme;
    Future<void> date(bool from) async {
      final now = DateTime.now();
      final d = await showDatePicker(
        context: context,
        initialDate: (from ? _d.dateFrom : _d.dateTo) ?? now,
        firstDate: DateTime(2024),
        lastDate: now,
      );
      if (d != null) {
        from ? _d.dateFrom = d : _d.dateTo = d;
        _touch();
      }
    }

    Widget dateButton(String label, DateTime? v, bool from) => Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => date(from),
            icon: const Icon(Icons.calendar_today_outlined, size: 18),
            label: Text(v == null ? label : AssignDraft.day(v)),
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52)),
          ),
        ),
        if (v != null)
          IconButton(
            tooltip: 'Clear',
            icon: const Icon(Icons.close),
            onPressed: () {
              from ? _d.dateFrom = null : _d.dateTo = null;
              _touch();
            },
          ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const StepHeader(title: 'Which calls should be repeated?'),
        Wrap(
          spacing: kGapS,
          runSpacing: kGapXS,
          children: [
            for (final s in data.statuses)
              FilterChip(
                label: Text(s),
                selected: _d.statuses.contains(s),
                onSelected: (v) {
                  v ? _d.statuses.add(s) : _d.statuses.remove(s);
                  _touch();
                },
              ),
          ],
        ),
        const SizedBox(height: kGapL),
        Text('Called between (optional)', style: text.titleSmall),
        const SizedBox(height: kGapS),
        Row(
          children: [
            Expanded(child: dateButton('From date', _d.dateFrom, true)),
            const SizedBox(width: kGapS),
            Expanded(child: dateButton('To date', _d.dateTo, false)),
          ],
        ),
        const SizedBox(height: kGapL),
        Text('Only calls made by (leave empty for everyone)', style: text.titleSmall),
        const SizedBox(height: kGapS),
        Wrap(
          spacing: kGapS,
          runSpacing: kGapXS,
          children: [
            for (final c in data.callers)
              FilterChip(
                label: Text('${c['name']}'),
                selected: _d.from.contains('${c['mob']}'),
                onSelected: (v) {
                  v ? _d.from.add('${c['mob']}') : _d.from.remove('${c['mob']}');
                  _touch();
                },
              ),
          ],
        ),
        const SizedBox(height: kGapL),
        Text('Narrow it down (optional)', style: text.titleSmall),
        const SizedBox(height: kGapS),
        _filters(),
      ],
    );
  }

  /// The contact filters, recounted whenever what decides the pool changes (statuses, dates, whose calls).
  Widget _filters() => FilterEditor(key: ValueKey(jsonEncode(_d.poolBody())), filters: _d.filters, poolBody: _d.poolBody(), onChanged: _touch);

  Widget _from(_Callers data) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const StepHeader(title: 'Whose calls should move?'),
        for (final c in data.callers)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _d.from.contains('${c['mob']}'),
            title: Text('${c['name']}'),
            subtitle: Text('${c['pending']} waiting for a first call', style: text.bodyMedium),
            onChanged: (v) {
              v == true ? _d.from.add('${c['mob']}') : _d.from.remove('${c['mob']}');
              _d.coords.remove('${c['mob']}');
              _touch();
            },
          ),
        const SizedBox(height: kGapL),
        Text('Narrow it down (optional)', style: text.titleSmall),
        const SizedBox(height: kGapS),
        _filters(),
      ],
    );
  }

  /// Step 2 of every flow: pick the coordinators (and, when assigning, how many contacts). What will happen is shown right below.
  Widget _coordinators(BuildContext context, _Callers data) {
    final text = Theme.of(context).textTheme;
    final title = switch (_d.kind) {
      AssignKind.followup => 'Who should call them again?',
      AssignKind.move => 'Who should get them?',
      _ => widget.reassignUnstarted ? 'Reassign unstarted calls to' : 'Who should get these contacts?',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StepHeader(title: title),
        if (_d.kind == AssignKind.assign) ...[
          TextFormField(
            initialValue: _d.limit == null ? '' : '${_d.limit}',
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
            decoration: const InputDecoration(labelText: 'How many contacts', hintText: 'All that match'),
            onChanged: (v) {
              final n = int.tryParse(v);
              _d.limit = (n == null || n == 0) ? null : n;
              _touch();
            },
          ),
          const SizedBox(height: kGapM),
        ],
        if (_d.kind == AssignKind.followup)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Same coordinator as before'),
            value: _d.keepPrevious,
            onChanged: (v) {
              _d.keepPrevious = v;
              _touch();
            },
          ),
        CoordinatorPicker(callers: data.callers, picked: _d.coords, exclude: _d.from, onChanged: _touch, onEditLimit: _editLimit),
        const SizedBox(height: kGapM),
        _preview(context),
        if (_d.coords.isEmpty) Text('Tick the coordinators to see what will happen.', style: text.bodyMedium),
      ],
    );
  }

  /// Changes a coordinator's max (the same limit as Admin → Calls) without leaving the wizard, then works out the plan again.
  Future<void> _editLimit(Map<String, dynamic> c) async {
    final ctl = TextEditingController(text: c['call_limit']?.toString() ?? '');
    final v = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Max for ${c['name']}'),
        content: TextField(
          controller: ctl,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Max contacts (empty = no limit)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, ctl.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    ctl.dispose();
    if (v == null || !mounted) return;
    try {
      await ref.read(adminRepoProvider).setCaller('${c['mob']}', {'call_limit': v.isEmpty ? null : int.tryParse(v)});
      ref.invalidate(_callersProvider(widget.event));
      _touch();
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    }
  }

  /// What will be saved, worked out by the server. Nothing has been written yet.
  Widget _preview(BuildContext context) {
    if (_d.coords.isEmpty) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    final c = context.colors;
    if (_planError != null) return StatusBanner(icon: Icons.error_outline, color: c.danger, text: _planError!);
    final p = _plan;
    if (_planning || p == null) {
      return const Padding(
        padding: EdgeInsets.all(kGapXL),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    int n(String k) => (p[k] as num?)?.toInt() ?? 0;
    final per = [for (final x in (p['per_coordinator'] as List)) Map<String, dynamic>.from(x as Map)];
    final taken = [for (final x in (p['taken_from'] as List)) Map<String, dynamic>.from(x as Map)];
    Widget line(String t, {Color? color, IconData? icon}) => Padding(
      padding: const EdgeInsets.only(top: kGapS),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[Icon(icon, size: 20, color: color), const SizedBox(width: kGapS)],
          Expanded(
            child: Text(t, style: text.bodyLarge?.copyWith(color: color)),
          ),
        ],
      ),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(kGapL),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(n('assignable') == 0 ? 'Nothing to assign' : '${n('assignable')} contacts will be assigned', style: text.headlineSmall),
            Text('${n('candidates')} contacts match', style: text.bodyLarge),
            if (n('kept_with_previous') > 0) line('${n('kept_with_previous')} go back to the coordinator who had them before'),
            if (n('leftover') > 0)
              line(
                '${n('leftover')} contacts cannot be given: the coordinators you chose have no room left under their limit. Choose more coordinators or raise a limit in Admin → Calls.',
                color: c.warning,
                icon: Icons.warning_amber,
              ),
            const SizedBox(height: kGapM),
            for (final x in per)
              Padding(
                padding: const EdgeInsets.only(top: kGapXS),
                child: Text(
                  '${x['name']}: +${x['add']}   (${x['limit'] == null ? 'no limit' : 'max ${x['limit']}'}, already ${x['has']})',
                  style: text.bodyLarge?.copyWith(color: x['full'] == true ? c.warning : null),
                ),
              ),
            if (taken.isNotEmpty) ...[
              const SizedBox(height: kGapM),
              Text('Taken from', style: text.titleSmall),
              for (final t in taken) Text('${t['name']}: ${t['count']}', style: text.bodyLarge),
            ],
          ],
        ),
      ),
    );
  }

  Widget _saving(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final done = _phase == _Phase.done;
    final saved = _done - _skipped;
    if (!done) {
      return Padding(
        padding: const EdgeInsets.all(kGapXL),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.cloud_upload_outlined, size: 48),
            const SizedBox(height: kGapM),
            Text('Saving…', style: text.headlineSmall),
            const SizedBox(height: kGapS),
            LinearProgressIndicator(value: _total == 0 ? null : _done / _total, minHeight: 8),
            const SizedBox(height: kGapS),
            Text('Assigned $_done of $_total. Keep this screen open.', style: text.bodyLarge),
          ],
        ),
      );
    }
    // What each coordinator received, from the server's answers to every saved batch (names, totals and limits come from the plan).
    final per = [for (final x in ((_plan?['per_coordinator'] as List?) ?? const [])) Map<String, dynamic>.from(x as Map)];
    final rows = [
      for (final x in per)
        (name: '${x['name']}', got: _added['${x['id']}'] ?? 0, has: (x['has'] as num?)?.toInt() ?? 0, limit: (x['limit'] as num?)?.toInt()),
    ].where((r) => r.got > 0).toList()..sort((a, b) => b.got.compareTo(a.got));
    final taken = [for (final x in ((_plan?['taken_from'] as List?) ?? const [])) Map<String, dynamic>.from(x as Map)];
    return ListView(
      padding: const EdgeInsets.all(kPagePadding),
      children: [
        Row(
          children: [
            Icon(Icons.check_circle, size: 40, color: context.colors.success),
            const SizedBox(width: kGapM),
            Expanded(child: Text('$saved contacts assigned', style: text.headlineSmall)),
          ],
        ),
        const SizedBox(height: kGapXS),
        Text(rows.length == 1 ? 'Given to 1 coordinator' : 'Shared between ${rows.length} coordinators', style: text.bodyLarge),
        if (_skipped > 0)
          Padding(
            padding: const EdgeInsets.only(top: kGapS),
            child: StatusBanner(icon: Icons.info_outline, text: '$_skipped skipped (already called or changed meanwhile).'),
          ),
        const SizedBox(height: kGapL),
        Text('Who got how many', style: text.titleMedium),
        const SizedBox(height: kGapS),
        for (final r in rows)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(kGapL),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(r.name, style: text.titleMedium)),
                      Text('+${r.got}', style: text.headlineSmall?.copyWith(color: context.colors.success)),
                    ],
                  ),
                  const SizedBox(height: kGapS),
                  if (r.limit != null) ...[
                    LinearProgressIndicator(value: r.limit == 0 ? 1 : ((r.has + r.got) / r.limit!).clamp(0, 1).toDouble(), minHeight: 6),
                    const SizedBox(height: kGapXS),
                  ],
                  Text(
                    'Now has ${r.has + r.got} contacts${r.limit == null ? '' : ' (max ${r.limit})'}  •  had ${r.has} before',
                    style: text.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
        if (taken.isNotEmpty) ...[
          const SizedBox(height: kGapM),
          Text('Taken from', style: text.titleMedium),
          const SizedBox(height: kGapS),
          for (final t in taken) Text('${t['name']}: ${t['count']}', style: text.bodyLarge),
        ],
      ],
    );
  }

  // ---------- bottom bar

  Widget? _bar(BuildContext context, _Callers data) {
    if (_phase == _Phase.saving) return null;
    if (_phase == _Phase.done) return WizardBar(nextLabel: 'Done', onNext: () => Navigator.pop(context, true));
    if (_step == AssignStep.start) return null;
    final last = _step == AssignStep.coordinators;
    final assignable = (_plan?['assignable'] as num?)?.toInt() ?? 0;
    final retry = _saveError != null;
    final ok = switch (_step) {
      AssignStep.calls => _d.statuses.isNotEmpty,
      AssignStep.from => _d.from.isNotEmpty,
      _ => true,
    };
    return WizardBar(
      onBack: _i > 0 ? () => _go(_i - 1) : null,
      nextLabel: last ? (retry ? 'Resume' : 'Assign') : 'Next',
      onNext: last
          ? (_plan == null || assignable == 0 ? null : _save)
          : ok
          ? () => _go(_i + 1)
          : null,
    );
  }
}
