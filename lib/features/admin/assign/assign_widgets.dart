import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  int? _total, _poolTotal;
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
                    TextButton(
                      onPressed: d == null
                          ? null
                          : () => setState(() {
                              if (allTicked) {
                                _ticked.clear();
                              } else {
                                for (final r in every) {
                                  _ticked[r.id] = r.title;
                                }
                              }
                            }),
                      child: Text(allTicked ? 'Clear' : 'Select all'),
                    ),
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

/// Pick coordinators and give each a Minimum and a Maximum for this assignment. Women are never offered.
class CoordinatorPicker extends StatelessWidget {
  const CoordinatorPicker({super.key, required this.callers, required this.group, this.exclude = const {}, required this.onChanged});
  final List<Map<String, dynamic>> callers;
  final GroupDraft group;
  final Set<String> exclude;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final receivers = [
      for (final c in callers)
        if (c['gender'] != 'F' && !exclude.contains('${c['mob']}')) c,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            TextButton(
              onPressed: () {
                for (final c in receivers) {
                  group.coords.putIfAbsent('${c['mob']}', () => CoordPick('${c['mob']}', '${c['name']}'));
                }
                onChanged();
              },
              child: const Text('Select all'),
            ),
            TextButton(
              onPressed: () {
                group.coords.clear();
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
    final pick = group.coords[mob];
    final nums = FilteringTextInputFormatter.digitsOnly;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: kGapM),
        child: Column(
          children: [
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: pick != null,
              title: Text('${c['name']}'),
              subtitle: Text('Waiting ${c['pending']}  •  Total ${c['assigned']}'),
              onChanged: (v) {
                if (v == true) {
                  group.coords[mob] = CoordPick(mob, '${c['name']}');
                } else {
                  group.coords.remove(mob);
                }
                onChanged();
              },
            ),
            if (pick != null)
              Padding(
                padding: const EdgeInsets.only(bottom: kGapM),
                child: Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        key: ValueKey('min$mob'),
                        initialValue: pick.min == 0 ? '' : '${pick.min}',
                        keyboardType: TextInputType.number,
                        inputFormatters: [nums, LengthLimitingTextInputFormatter(5)],
                        decoration: const InputDecoration(labelText: 'Minimum'),
                        onChanged: (v) {
                          pick.min = int.tryParse(v) ?? 0;
                          onChanged();
                        },
                      ),
                    ),
                    const SizedBox(width: kGapM),
                    Expanded(
                      child: TextFormField(
                        key: ValueKey('max$mob'),
                        initialValue: pick.max == null ? '' : '${pick.max}',
                        keyboardType: TextInputType.number,
                        inputFormatters: [nums, LengthLimitingTextInputFormatter(5)],
                        decoration: const InputDecoration(labelText: 'Maximum', hintText: 'No limit'),
                        onChanged: (v) {
                          final n = int.tryParse(v);
                          pick.max = (n == null || n == 0) ? null : n;
                          onChanged();
                        },
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
