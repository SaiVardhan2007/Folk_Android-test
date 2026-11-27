import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/layout.dart';
import '../../core/models.dart';
import '../../core/option_picker.dart';
import '../../core/options.dart';
import '../../core/widgets.dart';

/// The People table's filters. Every filter is a parameter of GET /admin/people; a list is sent as "a,b,c" (any of them),
/// and all filters must hold together. Names, labels and order live here, in one place.
const kSorts = {'newest': 'Newest first', 'oldest': 'Oldest first', 'name': 'Name A–Z', 'most': 'Most attended', 'recent': 'Recently attended'};

/// Fields that can be asked for as "not filled in yet" (the key is what the server accepts).
const kMissing = {
  'gender': 'Gender',
  'level': 'Level',
  'occupation': 'Occupation',
  'college': 'Company / College',
  'branch': 'Branch',
  'pg': 'PG / Residence',
  'area': 'Area of stay',
  'dob': 'Date of birth',
  'stay': 'Staying',
  'feedback': 'Feedback',
  'comments': 'Comments',
  'chanting': 'Chanting rounds',
};

const _kFeedbackFallback = ['Excellent', 'Good'];
const _kYesNo = {'yes': 'Has attended', 'no': 'Never attended'};

List<String> _list(String? v) => (v ?? '').split(',').where((x) => x.isNotEmpty).toList();

/// One removable chip under the search box: what it says, and which parameters it clears.
class FilterChipInfo {
  const FilterChipInfo(this.text, this.keys);
  final String text;
  final List<String> keys;
}

/// The active filters as short chips ("Branch: CSE, ECE", "Age 18–25", "No date of birth").
List<FilterChipInfo> describeFilters(Map<String, String> f, OptionLists opts, Bootstrap? boot) {
  final out = <FilterChipInfo>[];
  void add(String text, List<String> keys) => out.add(FilterChipInfo(text, keys));
  String titles(String key, List<Opt> from) {
    final ids = _list(f[key]);
    final names = [for (final id in ids) from.where((o) => o.id == id).map((o) => o.title).firstOrNull ?? id];
    return names.length > 3 ? '${names.length} selected' : names.join(', ');
  }

  String plain(String key, [String Function(String)? label]) {
    final v = _list(f[key]).map((x) => label?.call(x) ?? x).toList();
    return v.length > 3 ? '${v.length} selected' : v.join(', ');
  }

  if (_list(f['tag']).isNotEmpty) add('Role: ${plain('tag')}', ['tag']);
  if (_list(f['level']).isNotEmpty) add('Level: ${plain('level')}', ['level']);
  if (_list(f['gender']).isNotEmpty) add('Gender: ${plain('gender', genderLabel)}', ['gender']);
  if (_list(f['occupation']).isNotEmpty) add('Occupation: ${plain('occupation')}', ['occupation']);
  if (_list(f['stay']).isNotEmpty) add('Staying: ${plain('stay')}', ['stay']);
  if (_list(f['feedback']).isNotEmpty) add('Feedback: ${plain('feedback')}', ['feedback']);
  if (_list(f['college']).isNotEmpty) add('College: ${titles('college', opts[OptionList.college])}', ['college']);
  if (_list(f['branch']).isNotEmpty) add('Branch: ${titles('branch', opts[OptionList.branch])}', ['branch']);
  if (_list(f['pg']).isNotEmpty) add('PG: ${titles('pg', opts[OptionList.pg])}', ['pg']);
  if (_list(f['area']).isNotEmpty) add('Area: ${titles('area', opts[OptionList.area])}', ['area']);
  if (_list(f['guide']).isNotEmpty) {
    add('Guide: ${plain('guide', (id) => opts.guides.where((g) => g.id == id).map((g) => g.title).firstOrNull ?? id)}', ['guide']);
  }
  if (_list(f['skill']).isNotEmpty) add('Skill: ${titles('skill', opts[OptionList.skill])}', ['skill']);
  if (_list(f['interest']).isNotEmpty) add('Interest: ${titles('interest', opts[OptionList.interest])}', ['interest']);
  if (_list(f['event']).isNotEmpty) {
    add('Registered at: ${plain('event', (c) => boot?.eventsAndLists.where((e) => e.code == c).map((e) => e.name).firstOrNull ?? c)}', ['event']);
  }
  if (f['att'] != null) add(_kYesNo[f['att']] ?? '', ['att']);
  if ((f['sessions_min'] ?? '').isNotEmpty || (f['sessions_max'] ?? '').isNotEmpty) {
    add('Sessions ${_range(f['sessions_min'], f['sessions_max'])}', ['sessions_min', 'sessions_max']);
  }
  if ((f['age_min'] ?? '').isNotEmpty || (f['age_max'] ?? '').isNotEmpty) add('Age ${_range(f['age_min'], f['age_max'])}', ['age_min', 'age_max']);
  if ((f['from'] ?? '').isNotEmpty || (f['to'] ?? '').isNotEmpty) add('Registered ${_range(f['from'], f['to'])}', ['from', 'to']);
  if ((f['att_from'] ?? '').isNotEmpty || (f['att_to'] ?? '').isNotEmpty) {
    add('Last attended ${_range(f['att_from'], f['att_to'])}', ['att_from', 'att_to']);
  }
  for (final m in _list(f['missing'])) {
    add('No ${kMissing[m]?.toLowerCase() ?? m}', ['missing:$m']);
  }
  if (f['pending'] == '1') add('Awaiting approval', ['pending']);
  return out;
}

String _range(String? a, String? b) {
  final x = a ?? '', y = b ?? '';
  if (x.isNotEmpty && y.isNotEmpty) return '$x – $y';
  return x.isNotEmpty ? 'from $x' : 'up to $y';
}

/// Removes one chip's filter from [f] (a "missing:x" key removes just that field from the list).
Map<String, String> withoutFilter(Map<String, String> f, List<String> keys) {
  final out = {...f};
  for (final k in keys) {
    if (k.startsWith('missing:')) {
      final left = _list(out['missing'])..remove(k.substring(8));
      if (left.isEmpty) {
        out.remove('missing');
      } else {
        out['missing'] = left.join(',');
      }
    } else {
      out.remove(k);
    }
  }
  return out;
}

/// The filter sheet. Sections open and close so a long list of filters stays easy to scan; a number next to a section says how
/// many filters are set inside it. Returns the new parameters (without the search text), or null when closed.
class PeopleFilterSheet extends ConsumerStatefulWidget {
  const PeopleFilterSheet({super.key, required this.initial, required this.boot});
  final Map<String, String> initial;
  final Bootstrap? boot;
  @override
  ConsumerState<PeopleFilterSheet> createState() => _PeopleFilterSheetState();
}

class _PeopleFilterSheetState extends ConsumerState<PeopleFilterSheet> {
  late final Map<String, String> f = {...widget.initial}..remove('q');
  final _college = MultiOptionController(), _branch = MultiOptionController(), _pg = MultiOptionController(), _area = MultiOptionController();
  final _skill = MultiOptionController(), _interest = MultiOptionController();
  final _numbers = <String, TextEditingController>{};
  bool _seeded = false;

  static const _numberKeys = ['age_min', 'age_max', 'sessions_min', 'sessions_max'];

  @override
  void initState() {
    super.initState();
    for (final k in _numberKeys) {
      _numbers[k] = TextEditingController(text: f[k] ?? '');
    }
  }

  @override
  void dispose() {
    for (final c in [_college, _branch, _pg, _area, _skill, _interest]) {
      c.dispose();
    }
    for (final c in _numbers.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Puts the saved IDs back into the pickers once the lists are loaded.
  void _seed(OptionLists opts) {
    if (_seeded) return;
    _seeded = true;
    void one(MultiOptionController c, String key, OptionList l) {
      c.values = [for (final id in _list(f[key])) opts[l].where((o) => o.id == id).firstOrNull ?? Opt(id, id)];
    }

    one(_college, 'college', OptionList.college);
    one(_branch, 'branch', OptionList.branch);
    one(_pg, 'pg', OptionList.pg);
    one(_area, 'area', OptionList.area);
    one(_skill, 'skill', OptionList.skill);
    one(_interest, 'interest', OptionList.interest);
  }

  /// The current parameters: pickers and number boxes folded back into [f], empty ones left out.
  Map<String, String> _result() {
    final out = {...f};
    void ids(String key, MultiOptionController c) {
      final v = [for (final o in c.values) o.id].where((x) => x.isNotEmpty);
      if (v.isEmpty) {
        out.remove(key);
      } else {
        out[key] = v.join(',');
      }
    }

    ids('college', _college);
    ids('branch', _branch);
    ids('pg', _pg);
    ids('area', _area);
    ids('skill', _skill);
    ids('interest', _interest);
    for (final k in _numberKeys) {
      final v = _numbers[k]!.text.trim();
      if (v.isEmpty || v == '0') {
        out.remove(k);
      } else {
        out[k] = v;
      }
    }
    out.removeWhere((k, v) => v.isEmpty);
    return out;
  }

  void _toggle(String key, String value, bool on) => setState(() {
    final v = _list(f[key]);
    on ? (v.contains(value) ? null : v.add(value)) : v.remove(value);
    if (v.isEmpty) {
      f.remove(key);
    } else {
      f[key] = v.join(',');
    }
  });

  int _count(List<String> keys) => keys.where((k) => (f[k] ?? '').isNotEmpty || _numbers[k]?.text.trim().isNotEmpty == true).length;

  Widget _choices(String label, String key, Map<String, String> options) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: kGapS, bottom: kGapXS),
        child: Text(label, style: Theme.of(context).textTheme.labelLarge),
      ),
      Wrap(
        spacing: kGapS,
        runSpacing: kGapS,
        children: [
          for (final e in options.entries)
            FilterChip(label: Text(e.value), selected: _list(f[key]).contains(e.key), onSelected: (on) => _toggle(key, e.key, on)),
        ],
      ),
    ],
  );

  Widget _single(String label, String key, Map<String, String> options) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: kGapS, bottom: kGapXS),
        child: Text(label, style: Theme.of(context).textTheme.labelLarge),
      ),
      Wrap(
        spacing: kGapS,
        runSpacing: kGapS,
        children: [
          for (final e in options.entries)
            ChoiceChip(label: Text(e.value), selected: f[key] == e.key, onSelected: (on) => setState(() => on ? f[key] = e.key : f.remove(key))),
        ],
      ),
    ],
  );

  Widget _date(String label, String key) {
    final v = f[key] ?? '';
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        final now = DateTime.now();
        final d = await showDatePicker(
          context: context,
          initialDate: DateTime.tryParse(v) ?? now,
          firstDate: DateTime(2015),
          lastDate: now,
          initialEntryMode: DatePickerEntryMode.calendarOnly,
        );
        if (d != null) setState(() => f[key] = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}');
      },
      child: InputDecorator(
        isEmpty: v.isEmpty,
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: v.isEmpty
              ? const Icon(Icons.calendar_month_outlined)
              : IconButton(icon: const Icon(Icons.close), tooltip: 'Clear', onPressed: () => setState(() => f.remove(key))),
        ),
        child: Text(v),
      ),
    );
  }

  Widget _number(String label, String key) => TextField(
    controller: _numbers[key],
    keyboardType: TextInputType.number,
    decoration: InputDecoration(labelText: label),
    onChanged: (_) => setState(() {}),
  );

  Widget _section(String title, IconData icon, List<String> keys, List<Widget> children, {bool open = false}) {
    final n = _count(keys);
    return ExpansionTile(
      initiallyExpanded: open || n > 0,
      leading: Icon(icon),
      title: Row(
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          if (n > 0) ...[const SizedBox(width: 8), Badge(label: Text('$n'))],
        ],
      ),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: kGapM),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(height: kGapM), children[i]],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.boot;
    final opts = ref.watch(optionsProvider).value ?? const OptionLists();
    if (opts.lists.isNotEmpty) _seed(opts);
    final events = {for (final e in b?.eventsAndLists ?? <FolkEvent>[]) e.code: e.name};
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scroll) => Column(
        children: [
          Expanded(
            child: ListView(
              controller: scroll,
              padding: const EdgeInsets.symmetric(horizontal: kPagePadding),
              children: [
                Text('Filters and sort', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 10),
                OptionDropdown(
                  label: 'Sort by',
                  value: f['sort'] ?? 'newest',
                  options: kSorts.keys.toList(),
                  labelOf: (v) => kSorts[v]!,
                  allowNone: false,
                  onChanged: (v) => setState(() => f['sort'] = v),
                ),
                _section(
                  'Who',
                  Icons.person_outline,
                  ['tag', 'level', 'gender', 'occupation', 'stay', 'feedback', 'age_min', 'age_max'],
                  [
                    _choices('Role', 'tag', {for (final t in b?.tags ?? const <String>[]) t: t}),
                    _choices('Level', 'level', {for (final t in b?.levels ?? const <String>[]) t: t}),
                    _choices('Gender', 'gender', {
                      for (final t in b?.genders ?? const ['M', 'F']) t: genderLabel(t),
                    }),
                    _choices('Occupation', 'occupation', {for (final t in b?.occupations ?? const <String>[]) t: t}),
                    _choices('Staying', 'stay', {for (final t in b?.stays ?? const <String>[]) t: t}),
                    _choices('Feedback', 'feedback', {for (final t in (b?.feedbacks ?? _kFeedbackFallback)) t: t}),
                    Row(
                      children: [
                        Expanded(child: _number('Age from', 'age_min')),
                        const SizedBox(width: 12),
                        Expanded(child: _number('Age to', 'age_max')),
                      ],
                    ),
                  ],
                ),
                _section(
                  'Where from',
                  Icons.apartment_outlined,
                  ['college', 'branch', 'pg', 'area', 'guide'],
                  [
                    MultiOptionPicker(
                      controller: _college,
                      label: 'Company / College',
                      icon: Icons.apartment_outlined,
                      options: opts[OptionList.college],
                    ),
                    MultiOptionPicker(controller: _branch, label: 'Branch', icon: Icons.account_tree_outlined, options: opts[OptionList.branch]),
                    MultiOptionPicker(controller: _pg, label: 'PG / Residence', icon: Icons.home_outlined, options: opts[OptionList.pg]),
                    MultiOptionPicker(controller: _area, label: 'Area of stay', icon: Icons.location_on_outlined, options: opts[OptionList.area]),
                    _choices('FOLK Guide', 'guide', {for (final g in opts.guides) g.id: g.title}),
                  ],
                ),
                _section(
                  'Skills and interests',
                  Icons.star_outline,
                  ['skill', 'interest'],
                  [
                    MultiOptionPicker(controller: _skill, label: 'Skill (any of)', icon: Icons.star_outline, options: opts[OptionList.skill]),
                    MultiOptionPicker(
                      controller: _interest,
                      label: 'Interest (any of)',
                      icon: Icons.favorite_border,
                      options: opts[OptionList.interest],
                    ),
                  ],
                ),
                _section(
                  'Attendance and joining',
                  Icons.event_available_outlined,
                  ['att', 'sessions_min', 'sessions_max', 'att_from', 'att_to', 'event', 'from', 'to'],
                  [
                    _single('Attendance', 'att', _kYesNo),
                    Row(
                      children: [
                        Expanded(child: _number('Sessions at least', 'sessions_min')),
                        const SizedBox(width: 12),
                        Expanded(child: _number('Sessions at most', 'sessions_max')),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(child: _date('Last attended from', 'att_from')),
                        const SizedBox(width: 12),
                        Expanded(child: _date('Last attended to', 'att_to')),
                      ],
                    ),
                    _choices('Registered at', 'event', events),
                    Row(
                      children: [
                        Expanded(child: _date('Registered from', 'from')),
                        const SizedBox(width: 12),
                        Expanded(child: _date('Registered to', 'to')),
                      ],
                    ),
                  ],
                ),
                _section(
                  'Details not filled in',
                  Icons.edit_note_outlined,
                  ['missing'],
                  [
                    Text('Show people who have none of these yet.', style: Theme.of(context).textTheme.bodyMedium),
                    _choices('Missing', 'missing', kMissing),
                  ],
                ),
                _section(
                  'Account',
                  Icons.manage_accounts_outlined,
                  ['pending'],
                  [
                    _single('Approval', 'pending', {'1': 'Awaiting approval'}),
                  ],
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(kPagePadding, 8, kPagePadding, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, <String, String>{'sort': f['sort'] ?? 'newest'}),
                      child: const Text('Clear all'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(onPressed: () => Navigator.pop(context, _result()), child: const Text('Apply')),
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
