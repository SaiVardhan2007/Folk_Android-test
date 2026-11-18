import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_controller.dart';
import 'admin_repo.dart';
import '../../core/layout.dart';

const _sorts = {'newest': 'Newest first', 'oldest': 'Oldest first', 'name': 'Name A–Z', 'most': 'Most attended', 'recent': 'Recently attended'};

class PeopleTab extends ConsumerStatefulWidget {
  const PeopleTab({super.key});
  @override
  ConsumerState<PeopleTab> createState() => _PeopleTabState();
}

class _PeopleTabState extends ConsumerState<PeopleTab> with AutomaticKeepAliveClientMixin {
  final _scroll = ScrollController();
  final _search = TextEditingController();
  Timer? _debounce;
  Map<String, String> _filters = {'sort': 'newest'};
  final List<Person> _items = [];
  int _total = 0, _page = 0, _generation = 0;
  bool _loading = false, _done = false, _exporting = false;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300) _load();
    });
    _load(reset: true);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _search.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    // A new search or filter (reset) always starts over; an answer to an older request is ignored when it arrives.
    if (!reset && (_loading || _done)) return;
    if (reset) {
      _page = 0;
      _done = false;
      _items.clear();
    }
    final generation = reset ? ++_generation : _generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await ref.read(adminRepoProvider).people(_filters, _page + 1);
      if (!mounted || generation != _generation) return;
      setState(() {
        _page++;
        _items.addAll(r.people);
        _total = r.total;
        _done = _items.length >= r.total || r.people.isEmpty;
      });
    } on ApiException catch (e) {
      if (mounted && generation == _generation) setState(() => _error = e.message);
    } finally {
      if (mounted && generation == _generation) setState(() => _loading = false);
    }
  }

  void _apply(Map<String, String> f) {
    _filters = {
      for (final e in f.entries)
        if (e.value.isNotEmpty) e.key: e.value,
    };
    _filters.putIfAbsent('sort', () => 'newest');
    _load(reset: true);
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      await ref.read(adminRepoProvider).shareCsv('/admin/export/people', 'folk-people.csv', query: _filters);
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } catch (_) {
      if (mounted) showMessage(context, 'Could not share the file.', error: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _filterSheet() async {
    final boot = ref.read(bootstrapProvider).value;
    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => _FilterSheet(initial: _filters, boot: boot),
    );
    if (result != null) _apply({..._filters, ...result, 'q': _search.text.trim()});
  }

  Future<void> _manage(Person p) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => _ManageSheet(person: p),
    );
    if (changed == true) _load(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final text = Theme.of(context).textTheme;
    final active = _filters.entries.where((e) => e.key != 'sort' && e.key != 'q' && e.value.isNotEmpty).length;
    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: ListView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(kPagePadding, 12, kPagePadding, 24),
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _search,
                  decoration: const InputDecoration(labelText: 'Search name or mobile', prefixIcon: Icon(Icons.search)),
                  onChanged: (v) {
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 400), () => _apply({..._filters, 'q': v.trim()}));
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'Filters and sort',
                iconSize: 28,
                onPressed: _filterSheet,
                icon: Badge(isLabelVisible: active > 0, label: Text('$active'), child: const Icon(Icons.tune)),
              ),
              IconButton.filledTonal(
                tooltip: 'Export CSV',
                iconSize: 28,
                onPressed: _exporting ? null : _export,
                icon: _exporting
                    ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2.5))
                    : const Icon(Icons.ios_share),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text('$_total ${_total == 1 ? 'person' : 'people'}  •  ${_sorts[_filters['sort']] ?? ''}', style: text.bodyMedium),
          const SizedBox(height: 8),
          if (_error != null) ErrorView(message: _error!, onRetry: () => _load(reset: true)),
          for (final p in _items)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  onTap: () => _manage(p),
                  leading: CircleAvatar(radius: 24, child: Text(p.name.isEmpty ? '?' : p.name[0].toUpperCase())),
                  title: Text(p.name, style: text.titleSmall),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(p.mob),
                        if (p.level.isNotEmpty) Text('•  ${p.level}'),
                        Text('•  ${p.attendanceCount}× attended'),
                        if (p.lastAttendedOn.isNotEmpty) Text('•  last ${p.lastAttendedOn}'),
                      ],
                    ),
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(p.tag, style: text.labelMedium?.copyWith(color: p.isAdmin ? context.colors.brand : null)),
                      if (p.isPending)
                        Text('Awaiting approval', style: text.bodySmall?.copyWith(color: context.colors.warning))
                      else if (!p.isActive)
                        Text('Disabled', style: text.bodySmall?.copyWith(color: context.colors.danger))
                      else if (!p.hasPassword)
                        Text('No password', style: text.bodySmall?.copyWith(color: context.colors.warning)),
                    ],
                  ),
                ),
              ),
            ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (!_loading && _items.isEmpty && _error == null)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(child: Text('No one found.', style: text.bodyLarge)),
            ),
        ],
      ),
    );
  }
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.initial, required this.boot});
  final Map<String, String> initial;
  final Bootstrap? boot;
  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late final Map<String, String> f = {...widget.initial};

  @override
  Widget build(BuildContext context) {
    final b = widget.boot;
    return SheetBody(
      children: [
        Text('Filters and sort', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 14),
        FieldGrid(
          children: [
            OptionDropdown(
              label: 'Sort by',
              value: f['sort'] ?? 'newest',
              options: _sorts.keys.toList(),
              labelOf: (v) => _sorts[v]!,
              allowNone: false,
              onChanged: (v) => setState(() => f['sort'] = v),
            ),
            OptionDropdown(label: 'Role', value: f['tag'] ?? '', options: b?.tags ?? const [], onChanged: (v) => setState(() => f['tag'] = v)),
            OptionDropdown(label: 'Level', value: f['level'] ?? '', options: b?.levels ?? const [], onChanged: (v) => setState(() => f['level'] = v)),
            OptionDropdown(
              label: 'Gender',
              value: f['gender'] ?? '',
              options: const ['M', 'F'],
              labelOf: genderLabel,
              onChanged: (v) => setState(() => f['gender'] = v),
            ),
            OptionDropdown(
              label: 'Registered event',
              value: f['event'] ?? '',
              options: [for (final e in b?.eventsAndLists ?? <FolkEvent>[]) e.code],
              labelOf: (c) => b!.eventsAndLists.firstWhere((e) => e.code == c).name,
              onChanged: (v) => setState(() => f['event'] = v),
            ),
            OptionDropdown(
              label: 'Approval',
              value: f['pending'] ?? '',
              options: const ['1'],
              labelOf: (_) => 'Awaiting approval',
              onChanged: (v) => setState(() => f['pending'] = v),
            ),
            OptionDropdown(
              label: 'Password',
              value: f['pw'] ?? '',
              options: const ['set', 'unset'],
              labelOf: (v) => v == 'set' ? 'Has a password' : 'No password yet',
              onChanged: (v) => setState(() => f['pw'] = v),
            ),
            OptionDropdown(
              label: 'Attendance',
              value: f['att'] ?? '',
              options: const ['yes', 'no'],
              labelOf: (v) => v == 'yes' ? 'Has attended' : 'Never attended',
              onChanged: (v) => setState(() => f['att'] = v),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context, <String, String>{
                  'sort': 'newest',
                  'tag': '',
                  'level': '',
                  'gender': '',
                  'event': '',
                  'pw': '',
                  'att': '',
                  'pending': '',
                }),
                child: const Text('Clear all'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(onPressed: () => Navigator.pop(context, f), child: const Text('Apply')),
            ),
          ],
        ),
      ],
    );
  }
}

class _ManageSheet extends ConsumerStatefulWidget {
  const _ManageSheet({required this.person});
  final Person person;
  @override
  ConsumerState<_ManageSheet> createState() => _ManageSheetState();
}

class _ManageSheetState extends ConsumerState<_ManageSheet> {
  late String _tag = widget.person.tag;
  bool _busy = false;

  Future<void> _run(Future<void> Function() f, String done) async {
    setState(() => _busy = true);
    try {
      await f();
      if (!mounted) return;
      showMessage(context, done);
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    final p = widget.person;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Reset ${p.name}\'s password?'),
        content: const Text(
          'Their current password stops working. You will get a one-time code to give them, so they can choose a new password. You never see the password itself.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(100, 48), backgroundColor: context.colors.danger),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final code = await ref.read(adminRepoProvider).resetPassword(p.mob);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (c) => AlertDialog(
          title: const Text('One-time code'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Tell ${p.name} this code. It works once and expires in 24 hours. It will not be shown again.',
                style: Theme.of(c).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              SelectableText(code, style: Theme.of(c).textTheme.displaySmall?.copyWith(letterSpacing: 8, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('They open the app → "Have a code" → enter their number, this code and a new password.', style: Theme.of(c).textTheme.bodySmall),
            ],
          ),
          actions: [
            TextButton.icon(
              onPressed: () => Clipboard.setData(ClipboardData(text: code)),
              icon: const Icon(Icons.copy),
              label: const Text('Copy'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(100, 48)),
              onPressed: () => Navigator.pop(c),
              child: const Text('Done'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.person;
    final boot = ref.watch(bootstrapProvider).value;
    final me = ref.watch(authProvider).value;
    final isMe = me?.mob == p.mob;
    final repo = ref.read(adminRepoProvider);
    final text = Theme.of(context).textTheme;
    return SheetBody(
      children: [
        Row(
          children: [
            CircleAvatar(radius: 28, child: Text(p.name.isEmpty ? '?' : p.name[0].toUpperCase(), style: text.titleLarge)),
            const SizedBox(width: kGapM),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.name, style: text.titleLarge),
                  const SizedBox(height: 2),
                  Text(
                    p.isPending ? '${p.tag}  •  Awaiting approval' : (p.isActive ? p.tag : '${p.tag}  •  Disabled'),
                    style: text.bodyMedium?.copyWith(color: p.isPending ? context.colors.warning : (p.isActive ? null : context.colors.danger)),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: kGapL),
        DetailSection(title: 'Contact', rows: [
          ('Mobile', p.mob),
          ('Call number', p.callNo),
        ]),
        DetailSection(title: 'About', rows: [
          ('Gender', genderLabel(p.gender)),
          ('Level', p.level),
          ('Age', p.age > 0 ? '${p.age}' : ''),
          ('Occupation', p.occupation),
          ('Company / College', p.profession),
          ('PG / Residence', p.pgName),
          ('Staying', p.currentStay),
          ('Chanting rounds', p.chantingRounds > 0 ? '${p.chantingRounds}' : ''),
          ('Skills', p.skills),
          ('Interests', p.interests),
        ]),
        DetailSection(title: 'FOLK Guide', rows: [
          ('Folk Guide', p.folkGuide),
          ('Guide name', p.fgName),
          ('Guide mobile', p.fgMob),
        ]),
        DetailSection(title: 'Attendance', rows: [
          ('Attended', '${p.attendanceCount} time${p.attendanceCount == 1 ? '' : 's'}'),
          ('Last attended', p.lastAttendedOn),
          ('Joined', p.joined),
          ('Feedback', p.feedback),
          ('Comments', p.comments),
          ('Not interested', p.notInterested ? 'Yes (left out of call lists)' : ''),
        ]),
        const SizedBox(height: 4),
        if (isMe)
          Text('This is your own account: you can\'t change your role or password here.', style: text.bodyMedium)
        else ...[
          OptionDropdown(
            label: 'Role',
            value: _tag,
            options: boot?.tags ?? [p.tag],
            allowNone: false,
            icon: Icons.badge_outlined,
            onChanged: (v) => setState(() => _tag = v),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy || _tag == p.tag ? null : () => _run(() => repo.setRole(p.mob, _tag), 'Role changed to $_tag'),
            child: const Text('Save role'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(onPressed: _busy ? null : _reset, icon: const Icon(Icons.lock_reset), label: const Text('Reset password')),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _run(() => repo.setActive(p.mob, !p.isActive), p.isActive ? 'Account disabled' : 'Account enabled'),
            icon: Icon(p.isActive ? Icons.block : Icons.check_circle_outline),
            label: Text(p.isActive ? 'Disable account' : (p.isPending ? 'Approve account' : 'Enable account')),
            style: OutlinedButton.styleFrom(foregroundColor: p.isActive ? context.colors.danger : context.colors.success),
          ),
        ],
      ],
    );
  }
}
