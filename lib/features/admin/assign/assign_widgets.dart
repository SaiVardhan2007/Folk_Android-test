import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api.dart';
import '../../../core/layout.dart';
import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../admin_repo.dart';
import 'assign_models.dart';

/// The heading at the top of every wizard screen.
class StepHeader extends StatelessWidget {
  const StepHeader({super.key, required this.title, this.help});
  final String title;
  final String? help;
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: kGapL),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: text.titleLarge),
          if (help != null) ...[const SizedBox(height: kGapS), Text(help!, style: text.bodyLarge)],
        ],
      ),
    );
  }
}

String percent(int n, int of) => of <= 0 ? '0%' : '${(n * 100 / of).round()}%';

/// "Which contacts?": a live count, the chosen filters as chips, and one row per field that opens its numbers.
/// [outer] are filters that already apply (the pool's own, when editing a group), so a group can only narrow them further.
class FilterEditor extends ConsumerStatefulWidget {
  const FilterEditor({
    super.key,
    required this.filters,
    required this.poolBody,
    this.outer = const [],
    this.startAll = true,
    required this.onChanged,
  });
  final List<FilterDraft> filters;

  /// Whether a field without a filter shows every value ticked (the pool) or none ticked (a new group).
  final bool startAll;
  final List<FilterDraft> outer;
  final Map<String, dynamic> poolBody;
  final VoidCallback onChanged;
  @override
  ConsumerState<FilterEditor> createState() => _FilterEditorState();
}

class _FilterEditorState extends ConsumerState<FilterEditor> {
  int? _total, _poolTotal, _remaining, _assigned;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _count();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  List<Map<String, dynamic>> _json(Iterable<FilterDraft> f) => [for (final x in f) x.toJson()];

  /// One request shortly after the last change, never one per tap.
  void _count() {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 400), () async {
      final repo = ref.read(adminRepoProvider);
      try {
        final r = await repo.assignBreakdown({
          ...widget.poolBody,
          'filters': _json([...widget.outer, ...widget.filters]),
        });
        final p = widget.outer.isEmpty && widget.filters.isEmpty
            ? r
            : await repo.assignBreakdown({...widget.poolBody, 'filters': _json(widget.outer)});
        if (!mounted) return;
        setState(() {
          _total = (r['total'] as num).toInt();
          _poolTotal = (p['total'] as num).toInt();
          _remaining = (r['remaining'] as num?)?.toInt();
          _assigned = (r['assigned'] as num?)?.toInt();
          _error = null;
        });
      } on ApiException catch (e) {
        if (mounted) setState(() => _error = e.message);
      }
    });
  }

  Future<void> _open(String field) async {
    final mine = widget.filters.where((f) => f.field == field).firstOrNull;
    final result = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _BreakdownSheet(
        field: field,
        initial: mine,
        startAll: widget.startAll,
        poolBody: widget.poolBody,
        // The numbers show every value that is still possible, so this field's own filter is left out.
        others: _json([...widget.outer, ...widget.filters.where((f) => f.field != field)]),
      ),
    );
    if (result == null) return;
    setState(() {
      widget.filters.removeWhere((f) => f.field == field);
      if (result is FilterDraft) widget.filters.add(result);
    });
    widget.onChanged();
    _count();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = context.colors;
    final total = _total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(kGapL),
            child: _error != null
                ? Text(_error!, style: text.bodyLarge?.copyWith(color: c.danger))
                : total == null
                ? const LinearProgressIndicator()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.poolBody['kind'] == 'assign' && _remaining != null) ...[
                        if (_assigned != null) Text('$_assigned contacts already assigned', style: text.titleMedium),
                        Text('$_remaining contacts not assigned yet', style: text.titleMedium),
                        const SizedBox(height: kGapXS),
                      ],
                      Text('$total contacts match', style: text.headlineSmall),
                      if (widget.outer.isNotEmpty || widget.filters.isNotEmpty)
                        Text('${percent(total, _poolTotal ?? total)} of ${_poolTotal ?? total}', style: text.bodyLarge),
                      if (total == 0) Text('Nobody matches. Remove a filter.', style: text.bodyMedium?.copyWith(color: c.warning)),
                    ],
                  ),
          ),
        ),
        if (widget.filters.isNotEmpty) ...[
          const SizedBox(height: kGapM),
          Wrap(
            spacing: kGapS,
            runSpacing: kGapXS,
            children: [
              for (final f in widget.filters)
                InputChip(
                  label: Text(f.summary),
                  onDeleted: () {
                    setState(() => widget.filters.remove(f));
                    widget.onChanged();
                    _count();
                  },
                ),
            ],
          ),
        ],
        const SizedBox(height: kGapM),
        Card(
          child: Column(
            children: [
              for (final e in kPoolFields.entries)
                ListTile(
                  title: Text(e.value),
                  subtitle: Text(
                    widget.filters.where((f) => f.field == e.key).map((f) => f.valuesText).firstOrNull ?? (widget.startAll ? 'All' : '—'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _open(e.key),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The numbers for one field: every value with how many contacts have it, tick boxes, and "only these / everyone except these".
class _BreakdownSheet extends ConsumerStatefulWidget {
  const _BreakdownSheet({required this.field, required this.initial, required this.startAll, required this.poolBody, required this.others});
  final String field;
  final FilterDraft? initial;
  final bool startAll;
  final Map<String, dynamic> poolBody;
  final List<Map<String, dynamic>> others;
  @override
  ConsumerState<_BreakdownSheet> createState() => _BreakdownSheetState();
}

class _BreakdownSheetState extends ConsumerState<_BreakdownSheet> {
  final Map<String, String> _ticked = {};
  Map<String, dynamic>? _data;
  String? _error;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final r = await ref.read(adminRepoProvider).assignBreakdown({...widget.poolBody, 'field': widget.field, 'filters': widget.others});
      if (!mounted) return;
      setState(() {
        _data = r;
        if (widget.initial != null) {
          _ticked.addAll(widget.initial!.values);
        } else if (widget.startAll) {
          for (final x in _rows(r)) {
            _ticked[x.id] = x.title;
          }
        }
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _toggle(String id, String title, bool on) => setState(() => on ? _ticked[id] = title : _ticked.remove(id));

  List<({String id, String title, int count})> _rows(Map<String, dynamic> d) => [
    for (final v in (d['values'] as List)) (id: '${v['id']}', title: '${v['title']}', count: (v['count'] as num).toInt()),
    if (((d['empty'] as num?)?.toInt() ?? 0) > 0) (id: '', title: '(Empty)', count: (d['empty'] as num).toInt()),
  ];

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final d = _data;
    final base = (d?['base'] as num?)?.toInt() ?? 0;
    final every = d == null ? const <({String id, String title, int count})>[] : _rows(d);
    final rows = every.where((r) => r.title.toLowerCase().contains(_search.toLowerCase())).toList();
    final allTicked = every.isNotEmpty && every.every((r) => _ticked.containsKey(r.id));
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(kPagePadding, kGapL, kPagePadding, kGapS),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(kPoolFields[widget.field]!, style: text.titleLarge),
                Text(d == null ? 'Counting…' : '$base contacts', style: text.bodyMedium),
                const SizedBox(height: kGapM),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Search'),
                        onChanged: (v) => setState(() => _search = v),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    TextButton(
                      onPressed: d == null || allTicked
                          ? null
                          : () => setState(() {
                              for (final r in every) {
                                _ticked[r.id] = r.title;
                              }
                            }),
                      child: const Text('Select all'),
                    ),
                    // Untick everything in one tap, so a single value can be picked out of a long list.
                    TextButton(onPressed: d == null || _ticked.isEmpty ? null : () => setState(_ticked.clear), child: const Text('Clear all')),
                    const Spacer(),
                    if (_ticked.isNotEmpty) Text('${_ticked.length} selected', style: text.bodyMedium),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: _error != null
                ? ErrorView(message: _error!, onRetry: _load)
                : d == null
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: rows.length,
                    itemBuilder: (_, i) {
                      final r = rows[i];
                      return CheckboxListTile(
                        value: _ticked.containsKey(r.id),
                        onChanged: (v) => _toggle(r.id, r.title, v == true),
                        title: Text(r.title),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: kGapXS),
                          child: LinearProgressIndicator(value: base == 0 ? 0 : r.count / base, minHeight: 6),
                        ),
                        secondary: Text('${r.count}\n${percent(r.count, base)}', textAlign: TextAlign.end, style: text.bodyMedium),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(kPagePadding),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                  ),
                  const SizedBox(width: kGapM),
                  Expanded(
                    child: FilledButton(
                      // Everything ticked (or, for a group, nothing ticked) means no filter on this field.
                      onPressed: d == null || (widget.startAll && _ticked.isEmpty)
                          ? null
                          : () => Navigator.pop(context, allTicked || _ticked.isEmpty ? false : FilterDraft(widget.field, values: {..._ticked})),
                      child: const Text('Done'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pick the coordinators who receive the contacts. Women and switched-off coordinators are never offered. Each row shows the
/// coordinator's call limit and how many they already hold, so the room left is visible before anything is assigned.
class CoordinatorPicker extends StatelessWidget {
  const CoordinatorPicker({
    super.key,
    required this.callers,
    required this.picked,
    this.exclude = const {},
    required this.onChanged,
    this.onEditLimit,
  });
  final List<Map<String, dynamic>> callers;
  final Set<String> picked;
  final Set<String> exclude;
  final VoidCallback onChanged;

  /// When given, each row gets a small edit button to change that coordinator's max.
  final void Function(Map<String, dynamic> coordinator)? onEditLimit;

  @override
  Widget build(BuildContext context) {
    final receivers = [
      for (final c in callers)
        if (c['gender'] != 'F' && c['enabled'] != false && !exclude.contains('${c['mob']}')) c,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            TextButton(
              onPressed: () {
                picked.addAll([for (final c in receivers) '${c['mob']}']);
                onChanged();
              },
              child: const Text('Select all'),
            ),
            TextButton(
              onPressed: () {
                picked.clear();
                onChanged();
              },
              child: const Text('Clear'),
            ),
          ],
        ),
        if (receivers.isEmpty) Text('No active coordinators available.', style: Theme.of(context).textTheme.bodyLarge),
        for (final c in receivers) _row(context, c),
      ],
    );
  }

  Widget _row(BuildContext context, Map<String, dynamic> c) {
    final mob = '${c['mob']}';
    final limit = (c['call_limit'] as num?)?.toInt();
    final has = (c['assigned'] as num?)?.toInt() ?? 0;
    final room = limit == null ? null : (limit - has).clamp(0, limit);
    final full = room == 0;
    return Card(
      child: CheckboxListTile(
        value: picked.contains(mob),
        title: Text('${c['name']}'),
        subtitle: Text(
          limit == null ? 'No limit  •  Already has $has' : 'Max $limit  •  Already has $has  •  Room for $room more',
          style: TextStyle(color: full ? context.colors.warning : null),
        ),
        secondary: onEditLimit == null
            ? null
            : IconButton(tooltip: 'Change max', icon: const Icon(Icons.edit_outlined), onPressed: () => onEditLimit!(c)),
        onChanged: (v) {
          v == true ? picked.add(mob) : picked.remove(mob);
          onChanged();
        },
      ),
    );
  }
}

/// The bottom bar of every wizard screen: Back on the left, the main action on the right.
class WizardBar extends StatelessWidget {
  const WizardBar({super.key, this.onBack, required this.nextLabel, required this.onNext, this.note});
  final VoidCallback? onBack, onNext;
  final String nextLabel;
  final String? note;
  @override
  Widget build(BuildContext context) => Material(
    elevation: 8,
    color: Theme.of(context).colorScheme.surface,
    child: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(kPagePadding, kGapM, kPagePadding, kGapM),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (note != null)
              Padding(
                padding: const EdgeInsets.only(bottom: kGapS),
                child: Text(note!, style: Theme.of(context).textTheme.bodyMedium),
              ),
            Row(
              children: [
                if (onBack != null) ...[
                  Expanded(
                    child: OutlinedButton(onPressed: onBack, child: const Text('Back')),
                  ),
                  const SizedBox(width: kGapM),
                ],
                Expanded(
                  flex: 2,
                  child: FilledButton(onPressed: onNext, child: Text(nextLabel)),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
