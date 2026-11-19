import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/layout.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../admin/admin_repo.dart';
import '../auth/auth_controller.dart';
import '../calls/calls_screen.dart' show HistorySheet;
import '../register/person_form.dart';

const _sorts = {'newest': 'Newest first', 'oldest': 'Oldest first', 'name': 'Name A–Z', 'most': 'Most attended', 'recent': 'Recently attended'};

/// One column of the people table. All widths in one place.
class _Col {
  const _Col(this.label, this.width);
  final String label;
  final double width;
}

const _cName = _Col('Name', 200);
const _cMob = _Col('Mobile', 130);
const _cRole = _Col('Role', 120);
const _cLevel = _Col('Level', 150);
const _cGender = _Col('Gender', 90);
const _cAge = _Col('Age', 70);
const _cOcc = _Col('Occupation', 130);
const _cCompany = _Col('Company / College', 190);
const _cPg = _Col('PG / Residence', 170);
const _cStay = _Col('Staying', 140);
const _cGuide = _Col('FOLK Guide', 130);
const _cCalls = _Col('Calls', 90);
const _cSessions = _Col('Sessions', 110);
const _cLast = _Col('Last attended', 140);
const _cJoined = _Col('Joined', 120);
const _cStatus = _Col('Status', 150);
const _columns = [_cName, _cMob, _cRole, _cLevel, _cGender, _cAge, _cOcc, _cCompany, _cPg, _cStay, _cGuide, _cCalls, _cSessions, _cLast, _cJoined, _cStatus];
final double _tableWidth = _columns.fold<double>(0, (t, c) => t + c.width);
const double _rowHeight = 60;

/// Everyone in the system as a table: one row per person, one column per detail. Tap a row to edit every field;
/// tap the Calls or Sessions number to see that person's log.
class PeopleScreen extends ConsumerStatefulWidget {
  const PeopleScreen({super.key});
  @override
  ConsumerState<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends ConsumerState<PeopleScreen> with AutomaticKeepAliveClientMixin {
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
      builder: (c) => _EditSheet(person: p),
    );
    if (changed == true) _load(reset: true);
  }

  void _history(Person p, {required bool calls}) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => HistorySheet(mob: p.mob, name: p.name, calls: calls),
  );

  Widget _count(int n, VoidCallback onTap) => FilledButton.tonal(
    onPressed: onTap,
    style: FilledButton.styleFrom(minimumSize: const Size(48, 36), padding: const EdgeInsets.symmetric(horizontal: 14), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
    child: Text('$n'),
  );

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final text = Theme.of(context).textTheme;
    final active = _filters.entries.where((e) => e.key != 'sort' && e.key != 'q' && e.value.isNotEmpty).length;
    final line = Theme.of(context).dividerColor;

    Widget cell(_Col c, Widget child) => SizedBox(
      width: c.width,
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Align(alignment: Alignment.centerLeft, child: child)),
    );
    Widget plain(_Col c, String v) => cell(c, Text(v.isEmpty ? '—' : v, maxLines: 2, overflow: TextOverflow.ellipsis, style: text.bodyMedium));

    Widget row(Person p) {
      final status = p.isPending ? 'Awaiting approval' : (p.isActive ? 'Active' : 'Disabled');
      final statusColor = p.isPending ? context.colors.warning : (p.isActive ? context.colors.success : context.colors.danger);
      return InkWell(
        onTap: () => _manage(p),
        child: Container(
          height: _rowHeight,
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: line))),
          child: Row(
            children: [
              cell(_cName, Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: text.titleSmall)),
              plain(_cMob, p.mob),
              cell(_cRole, Text(p.tag, style: text.labelLarge?.copyWith(color: p.isAdmin ? context.colors.brand : null))),
              plain(_cLevel, p.level),
              plain(_cGender, genderLabel(p.gender)),
              plain(_cAge, p.age > 0 ? '${p.age}' : ''),
              plain(_cOcc, p.occupation),
              plain(_cCompany, p.profession),
              plain(_cPg, p.pgName),
              plain(_cStay, p.currentStay),
              plain(_cGuide, p.folkGuide),
              cell(_cCalls, _count(p.callsCount, () => _history(p, calls: true))),
              cell(_cSessions, _count(p.attendanceCount, () => _history(p, calls: false))),
              plain(_cLast, p.lastAttendedOn),
              plain(_cJoined, p.joined),
              cell(_cStatus, Text(status, style: text.labelLarge?.copyWith(color: statusColor))),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(kPagePadding, 12, kPagePadding, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
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
              Text('$_total ${_total == 1 ? 'person' : 'people'}  •  ${_sorts[_filters['sort']] ?? ''}  •  tap a row to edit', style: text.bodyMedium),
              const SizedBox(height: 8),
              if (_error != null) ErrorView(message: _error!, onRetry: () => _load(reset: true)),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) => Scrollbar(
              notificationPredicate: (n) => n.depth == 0,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: kPagePadding),
                child: SizedBox(
                  width: math.max(box.maxWidth - 2 * kPagePadding, _tableWidth),
                  child: Column(
                    children: [
                      Container(
                        height: 48,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHigh,
                          border: Border(bottom: BorderSide(color: line)),
                        ),
                        child: Row(
                          children: [
                            for (final c in _columns) cell(c, Text(c.label, style: text.labelLarge)),
                          ],
                        ),
                      ),
                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: () => _load(reset: true),
                          child: ListView.builder(
                            controller: _scroll,
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.only(bottom: 24),
                            itemCount: _items.length + 1,
                            itemBuilder: (context, i) {
                              if (i < _items.length) return row(_items[i]);
                              if (_loading) {
                                return const Padding(
                                  padding: EdgeInsets.all(20),
                                  child: Center(child: CircularProgressIndicator()),
                                );
                              }
                              if (_items.isEmpty && _error == null) {
                                return Padding(
                                  padding: const EdgeInsets.all(32),
                                  child: Text('No one found.', style: text.bodyLarge),
                                );
                              }
                              return const SizedBox.shrink();
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
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

/// Edit every detail of one person, their role and whether the account works.
class _EditSheet extends ConsumerStatefulWidget {
  const _EditSheet({required this.person});
  final Person person;
  @override
  ConsumerState<_EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends ConsumerState<_EditSheet> {
  final _form = PersonFormController();
  late final _mob = TextEditingController(text: widget.person.mob);
  late final _guide = TextEditingController(text: widget.person.folkGuide);
  late final _venue = TextEditingController(text: widget.person.venue);
  late final _map = TextEditingController(text: widget.person.gmapLink);
  late String _tag = widget.person.tag;
  late bool _active = widget.person.isActive;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _form.load(widget.person);
  }

  @override
  void dispose() {
    _form.dispose();
    _mob.dispose();
    _guide.dispose();
    _venue.dispose();
    _map.dispose();
    super.dispose();
  }

  Future<void> _save(bool locked) async {
    final p = widget.person;
    if (_form.name.text.trim().isEmpty) {
      showMessage(context, 'Enter the name.', error: true);
      return;
    }
    setState(() => _busy = true);
    final repo = ref.read(adminRepoProvider);
    try {
      await repo.updatePerson(p.mob, {
        ..._form.toJson(),
        // A cleared number box means "none"; the shared form leaves these out when empty.
        'age': int.tryParse(_form.age.text.trim()) ?? 0,
        'chanting_rounds': int.tryParse(_form.chanting.text.trim()) ?? 0,
        'folk_guide': _guide.text.trim(),
        'venue': _venue.text.trim(),
        'gmap_link': _map.text.trim(),
        if (_mob.text.trim() != p.mob) 'new_mob': _mob.text.trim(),
      });
      final mob = _mob.text.trim().isEmpty ? p.mob : _mob.text.trim();
      if (!locked && _tag != p.tag) await repo.setRole(mob, _tag);
      if (!locked && _active != p.isActive) await repo.setActive(mob, _active);
      if (!mounted) return;
      showMessage(context, 'Saved');
      Navigator.pop(context, true);
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
    final text = Theme.of(context).textTheme;
    // Your own account can't be demoted or disabled here, and the main admin's can only be changed in ERPNext.
    final locked = me?.mob == p.mob;
    return SheetBody(
      children: [
        Text(p.name, style: text.titleLarge),
        const SizedBox(height: 2),
        Text(
          p.isPending ? 'Awaiting approval' : '${p.attendanceCount} session${p.attendanceCount == 1 ? '' : 's'}  •  ${p.callsCount} call${p.callsCount == 1 ? '' : 's'}',
          style: text.bodyMedium,
        ),
        const SizedBox(height: kGapL),
        FieldGrid(
          children: [
            TextField(
              controller: _mob,
              keyboardType: TextInputType.phone,
              enabled: !locked,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ \-]')), LengthLimitingTextInputFormatter(15)],
              decoration: const InputDecoration(labelText: 'Mobile', helperText: 'Also how they sign in', prefixIcon: Icon(Icons.phone_android)),
            ),
            OptionDropdown(
              label: 'Role',
              value: _tag,
              options: boot?.tags ?? [p.tag],
              allowNone: false,
              icon: Icons.badge_outlined,
              onChanged: locked ? (_) {} : (v) => setState(() => _tag = v),
            ),
          ],
        ),
        const SizedBox(height: kGapM),
        PersonFields(form: _form, boot: boot, requireLevel: false),
        const SizedBox(height: kGapM),
        FieldGrid(
          children: [
            TextField(controller: _guide, decoration: const InputDecoration(labelText: 'FOLK Guide (code)', prefixIcon: Icon(Icons.badge_outlined))),
            TextField(controller: _venue, decoration: const InputDecoration(labelText: 'Venue', prefixIcon: Icon(Icons.place_outlined))),
            TextField(controller: _map, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Map link', prefixIcon: Icon(Icons.map_outlined))),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _active,
          onChanged: locked ? null : (v) => setState(() => _active = v),
          title: Text(p.isPending && !_active ? 'Approve this account' : 'Account enabled'),
          subtitle: locked ? const Text('This is your own account: you can\'t change your role or disable it here.') : null,
        ),
        const SizedBox(height: kGapS),
        FilledButton.icon(onPressed: _busy ? null : () => _save(locked), icon: const Icon(Icons.save_outlined), label: Text(_busy ? 'Saving…' : 'Save changes')),
      ],
    );
  }
}
