import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api.dart';
import '../../../core/layout.dart';
import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../admin_repo.dart';
import 'assign_models.dart';
import 'assign_widgets.dart';
import 'group_editor.dart';

typedef _Callers = ({List<Map<String, dynamic>> callers, List<String> statuses});
final _callersProvider = FutureProvider.autoDispose.family<_Callers, String>((ref, event) => ref.read(adminRepoProvider).callers(event: event));

/// Admin → Calls → Assign calls. A step-by-step wizard: one question per screen, a Review before anything is saved,
/// then the plan is written in small repeatable batches. There is no way to jump around in the middle.
class AssignWizard extends ConsumerStatefulWidget {
  const AssignWizard({super.key, required this.event, required this.eventName, this.reassignUnstarted = false});
  final String event, eventName;

  /// "Reassign Unstarted": skips the start screen and moves every call nobody has made to the coordinators picked.
  final bool reassignUnstarted;
  @override
  ConsumerState<AssignWizard> createState() => _AssignWizardState();
}

enum _Phase { edit, saving, done }

class _AssignWizardState extends ConsumerState<AssignWizard> {
  late final AssignDraft _d = AssignDraft(widget.event)
    ..kind = widget.reassignUnstarted ? AssignKind.move : null
    ..all = widget.reassignUnstarted;
  int _i = 0;
  _Phase _phase = _Phase.edit;

  Map<String, dynamic>? _plan;
  bool _planning = false;
  String? _planError, _saveError;
  List<Map<String, dynamic>> _batches = const [];
  final Set<int> _finished = {};
  List<String> _release = const [];
  Map<String, dynamic>? _sizes;
  int _released = 0, _done = 0, _skipped = 0, _total = 0;
  final Map<String, int> _added = {}; // contacts added per coordinator, sent once at the end so each coordinator gets one notification

  List<AssignStep> get _steps => stepsFor(_d.kind, reassign: widget.reassignUnstarted);
  AssignStep get _step => _steps[_i];
  bool get _busy => _phase == _Phase.saving;

  /// 1 when the first step is the start screen (not counted as a step).
  int get _first => _steps.first == AssignStep.start ? 1 : 0;

  void _go(int to) {
    setState(() {
      _i = to;
      _plan = null;
      _planError = null;
    });
    if (_step == AssignStep.review) _makePlan();
    if (_step == AssignStep.groups) _loadSizes();
  }

  /// How many contacts each group holds, and whether two groups share contacts. Numbers only.
  Future<void> _loadSizes() async {
    try {
      final r = await ref.read(adminRepoProvider).assignGroupSizes(_d.planBody());
      if (mounted && _step == AssignStep.groups) setState(() => _sizes = r);
    } on ApiException {
      if (mounted) setState(() => _sizes = null);
    }
  }

  /// Any change to the choices invalidates the plan, so what is saved is always what was reviewed.
  void _touch() {
    setState(() {
      _plan = null;
      _planError = null;
      _sizes = null;
    });
    if (_step == AssignStep.groups) _loadSizes();
  }

  Future<void> _makePlan() async {
    setState(() => _planning = true);
    try {
      final r = await ref.read(adminRepoProvider).planAssign(_d.planBody());
      if (!mounted) return;
      setState(() {
        _plan = r;
        _batches = makeBatches(r);
        _release = [for (final x in (r['release'] as List)) '$x'];
        _finished.clear();
        _released = _done = _skipped = 0;
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

  /// Writes every batch that is not finished yet, then removes the replaced calls. Safe to run again after a failure.
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
    // Only after every contact is saved are the replaced calls removed, so a failure never leaves anyone without a call.
    if (failure == null) {
      try {
        while (_released < _release.length) {
          final part = _release.sublist(_released, (_released + 100).clamp(0, _release.length));
          await _retry(() async => {'removed': await repo.releaseAssign(widget.event, part)});
          if (!mounted) return;
          setState(() => _released += part.length);
        }
      } catch (e) {
        failure = e;
      }
    }
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
          AssignStep.groups => _groups(context, data),
          AssignStep.calls => _calls(context, data),
          AssignStep.narrow => _narrow(),
          AssignStep.coordinators => _coordinators(data),
          AssignStep.from => _from(data),
          AssignStep.to => _to(data),
          AssignStep.review => _review(context),
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

  Widget _groups(BuildContext context, _Callers data) {
    final text = Theme.of(context).textTheme;
    final sizes = _sizes;
    int? size(int n) => sizes == null ? null : ((sizes['sizes'] as List)[n] as num).toInt();
    final overlaps = [for (final o in (sizes?['overlaps'] as List? ?? const [])) Map<String, dynamic>.from(o as Map)];
    Future<void> edit(
      GroupDraft g,
      String title, {
      required bool rest,
      required void Function(GroupDraft) save,
      List<GroupDraft> others = const [],
    }) async {
      final r = await Navigator.push<GroupDraft>(
        context,
        MaterialPageRoute(
          builder: (_) => GroupEditorPage(group: g, title: title, rest: rest, draft: _d, callers: data.callers, others: others),
        ),
      );
      if (r != null) {
        save(r);
        _touch();
      }
    }

    String who(GroupDraft g) => g.leave
        ? 'Left unassigned'
        : g.coords.isEmpty
        ? 'No coordinator yet'
        : g.coords.values.map((c) => c.name).join(', ');
    Widget card(
      String title,
      GroupDraft g, {
      required bool rest,
      required void Function(GroupDraft) save,
      int? count,
      List<GroupDraft> others = const [],
      VoidCallback? onDelete,
    }) => Card(
      child: Padding(
        padding: const EdgeInsets.all(kGapL),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: text.titleMedium)),
                if (count != null) Text('$count contacts', style: text.titleMedium),
              ],
            ),
            const SizedBox(height: kGapXS),
            if (!rest) Text(g.contactsText, style: text.bodyMedium),
            Text('→ ${who(g)}', style: text.bodyLarge?.copyWith(color: g.ready ? null : context.colors.warning)),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => edit(g, title, rest: rest, save: save, others: others),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit'),
                ),
                if (onDelete != null) IconButton(tooltip: 'Remove', icon: const Icon(Icons.delete_outline), onPressed: onDelete),
              ],
            ),
          ],
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const StepHeader(title: 'Who calls whom?'),
        for (var n = 0; n < _d.groups.length; n++)
          card(
            'Group ${n + 1}',
            _d.groups[n],
            rest: false,
            count: size(n),
            save: (g) => _d.groups[n] = g,
            others: [
              for (var k = 0; k < _d.groups.length; k++)
                if (k != n) _d.groups[k],
            ],
            onDelete: () {
              _d.groups.removeAt(n);
              _touch();
            },
          ),
        for (final o in overlaps)
          Padding(
            padding: const EdgeInsets.only(bottom: kGapS),
            child: StatusBanner(
              icon: Icons.error_outline,
              color: context.colors.danger,
              text: 'Group ${(o['a'] as int) + 1} and Group ${(o['b'] as int) + 1} share ${o['count']} contacts. Edit one of them.',
            ),
          ),
        card(
          _d.groups.isEmpty ? 'All the contacts you chose' : 'Everyone else',
          _d.rest,
          rest: true,
          count: sizes == null ? null : (sizes['rest'] as num).toInt(),
          save: (g) => _d.rest = g,
        ),
        OutlinedButton.icon(
          onPressed: () => edit(GroupDraft(), 'Group ${_d.groups.length + 1}', rest: false, save: _d.groups.add, others: List.of(_d.groups)),
          icon: const Icon(Icons.add),
          label: const Text('Add a group'),
        ),
      ],
    );
  }

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
      ],
    );
  }

  Widget _narrow() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const StepHeader(title: 'Narrow it down (optional)'),
      FilterEditor(filters: _d.filters, poolBody: _d.poolBody(), onChanged: _touch),
    ],
  );

  Widget _coordinators(_Callers data) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const StepHeader(title: 'Who should call them again?'),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Same coordinator as before'),
        value: _d.rest.keepPrevious,
        onChanged: (v) {
          _d.rest.keepPrevious = v;
          _touch();
        },
      ),
      const Divider(),
      CoordinatorPicker(callers: data.callers, group: _d.rest, onChanged: _touch),
    ],
  );

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
              _d.rest.coords.remove('${c['mob']}');
              _touch();
            },
          ),
      ],
    );
  }

  Widget _to(_Callers data) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      StepHeader(title: widget.reassignUnstarted ? 'Reassign unstarted calls to' : 'Who should get them?'),
      if (!widget.reassignUnstarted)
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Also give contacts nobody has yet'),
          value: _d.includeNew,
          onChanged: (v) {
            _d.includeNew = v;
            _touch();
          },
        ),
      const Divider(),
      CoordinatorPicker(callers: data.callers, group: _d.rest, exclude: _d.from, onChanged: _touch),
    ],
  );

  Widget _review(BuildContext context) {
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
    final groups = [for (final x in (p['groups'] as List)) Map<String, dynamic>.from(x as Map)];
    final taken = [for (final x in (p['taken_from'] as List)) Map<String, dynamic>.from(x as Map)];
    final short = per.where((x) => x['short'] == true).toList();
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const StepHeader(title: 'Check before saving'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(kGapL),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(n('assignable') == 0 ? 'Nothing to assign' : '${n('assignable')} contacts will be assigned', style: text.headlineSmall),
                Text('${n('candidates')} contacts matched', style: text.bodyLarge),
                if (n('kept_with_previous') > 0) line('${n('kept_with_previous')} go back to the coordinator who had them before'),
                if (n('leftover') > 0)
                  line(
                    '${n('leftover')} contacts are LEFT OVER: every coordinator has reached their Maximum. Go Back and raise a Maximum or add a coordinator.',
                    color: c.danger,
                    icon: Icons.warning_amber,
                  ),
                if (n('left_by_choice') > 0) line('${n('left_by_choice')} contacts stay unassigned, as you chose.', icon: Icons.info_outline),
                for (final s in short)
                  line(
                    '${s['name']} gets ${s['add']}, below the Minimum of ${s['min']}: not enough contacts.',
                    color: c.warning,
                    icon: Icons.warning_amber,
                  ),
                if (n('replaced') > 0)
                  line(
                    '${n('replaced')} calls from the earlier assignment that nobody has made will be removed. Calls already made stay.',
                    icon: Icons.autorenew,
                  ),
                if (taken.isNotEmpty) ...[
                  const SizedBox(height: kGapM),
                  Text('Taken from', style: text.titleSmall),
                  for (final t in taken) Text('${t['name']}: ${t['count']}', style: text.bodyLarge),
                ],
              ],
            ),
          ),
        ),
        if (groups.length > 1)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(kGapL),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('By group', style: text.titleMedium),
                  for (final g in groups) Text('${g['name']}: ${g['given']} of ${g['matched']} contacts', style: text.bodyLarge),
                ],
              ),
            ),
          ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(kGapL),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Each coordinator gets', style: text.titleMedium),
                for (final x in per)
                  Padding(
                    padding: const EdgeInsets.only(top: kGapS),
                    child: Text(
                      '${x['name']}: ${x['add']}   (minimum ${x['min']}, ${x['max'] == null ? 'no maximum' : 'maximum ${x['max']}'})',
                      style: text.bodyLarge?.copyWith(color: x['short'] == true ? c.warning : null),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _saving(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final done = _phase == _Phase.done;
    final saved = _done - _skipped;
    return Padding(
      padding: const EdgeInsets.all(kGapXL),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(done ? Icons.check_circle : Icons.cloud_upload_outlined, size: 48, color: done ? context.colors.success : null),
          const SizedBox(height: kGapM),
          Text(done ? '$saved contacts assigned' : 'Saving…', style: text.headlineSmall),
          const SizedBox(height: kGapS),
          if (done) ...[
            if (_skipped > 0) Text('$_skipped skipped (already called or changed meanwhile).', style: text.bodyLarge),
            if (_release.isNotEmpty) Text('${_release.length} earlier calls nobody had made were replaced.', style: text.bodyLarge),
          ] else ...[
            LinearProgressIndicator(value: _total == 0 ? null : _done / _total, minHeight: 8),
            const SizedBox(height: kGapS),
            Text(_done < _total ? 'Assigned $_done of $_total. Keep this screen open.' : 'Removing replaced calls…', style: text.bodyLarge),
          ],
        ],
      ),
    );
  }

  // ---------- bottom bar

  Widget? _bar(BuildContext context, _Callers data) {
    if (_phase == _Phase.saving) return null;
    if (_phase == _Phase.done) return WizardBar(nextLabel: 'Done', onNext: () => Navigator.pop(context, true));
    if (_step == AssignStep.start) return null;
    final last = _step == AssignStep.review;
    final assignable = (_plan?['assignable'] as num?)?.toInt() ?? 0;
    final retry = _saveError != null;
    final ok = switch (_step) {
      AssignStep.calls => _d.statuses.isNotEmpty,
      AssignStep.from => _d.from.isNotEmpty,
      AssignStep.groups => _d.rest.ready && _d.groups.every((g) => g.readyAsGroup) && _sizes != null && (_sizes!['overlaps'] as List).isEmpty,
      AssignStep.coordinators || AssignStep.to => _d.rest.coords.isNotEmpty,
      _ => true,
    };
    return WizardBar(
      onBack: _i > 0 ? () => _go(_i - 1) : null,
      nextLabel: last ? (retry ? 'Resume' : 'Assign now') : 'Next',
      onNext: last
          ? (_plan == null || assignable + _released == 0 && _release.isEmpty ? null : _save)
          : ok
          ? () => _go(_i + 1)
          : null,
    );
  }
}
