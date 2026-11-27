// The choices made in the assign wizard. Plain data, no widgets, so the rules are easy to test.

/// The fields a hand-out can be narrowed by (the server accepts only these). Label and order live here, in one place.
const kPoolFields = <String, String>{
  'college': 'College / Company',
  'branch': 'Branch',
  'area': 'Area of stay',
  'level': 'Level',
  'gender': 'Gender',
  'occupation': 'Occupation',
  'guide': 'Guide',
  'reg_event': 'Registered at (event)',
  'attended': 'Attended before',
  'skill': 'Skill',
  'interest': 'Interest',
};

enum AssignKind { assign, followup, move }

/// One filter: keep only contacts that have one of the ticked values. The empty id means "no value".
class FilterDraft {
  FilterDraft(this.field, {Map<String, String>? values}) : values = values ?? {};
  final String field;

  /// id -> title (titles are kept only to show the filter as text).
  final Map<String, String> values;

  FilterDraft copy() => FilterDraft(field, values: {...values});
  Map<String, dynamic> toJson() => {'field': field, 'mode': 'only', 'values': values.keys.toList()};

  /// The ticked values as text, short when many are ticked.
  String get valuesText => values.length > 3 ? '${values.length} selected' : values.values.join(', ');
  String get summary => '${kPoolFields[field] ?? field}: $valuesText';
}

/// Everything the admin has chosen, in the shape the server's plan endpoint expects.
class AssignDraft {
  /// Everyone starts selected except women: coordinators are men, so female contacts are not called unless the admin ticks them.
  AssignDraft(this.event) {
    filters.add(FilterDraft('gender', values: {'M': 'Male', '': '(Empty)'}));
  }
  final String event;
  AssignKind? kind;
  final List<FilterDraft> filters = [];
  final Set<String> statuses = {}, from = {};
  DateTime? dateFrom, dateTo;

  /// "Reassign Unstarted": move every call nobody has made, from everyone, to the chosen coordinators.
  bool all = false;

  /// The coordinators (by mobile number) who receive the contacts. Their call limit and what they already hold are applied by the server.
  final Set<String> coords = {};
  bool keepPrevious = false;

  /// How many contacts to assign now; null = every contact that matches (as far as the coordinators' limits allow).
  int? limit;

  static String day(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// What decides which contacts can be drawn from (before the admin's filters).
  Map<String, dynamic> poolBody() => {
    'kind': kind?.name,
    'event': event,
    'statuses': statuses.toList(),
    'from': from.toList(),
    'all': all,
    if (dateFrom != null) 'date_from': day(dateFrom!),
    if (dateTo != null) 'date_to': day(dateTo!),
  };

  Map<String, dynamic> planBody() => {
    ...poolBody(),
    'filters': [for (final f in filters) f.toJson()],
    'limit': kind == AssignKind.assign ? limit ?? 0 : 0,
    'to': {'coordinators': coords.toList(), 'keep_previous': keepPrevious},
  };
}

/// The wizard's screens, in order, for each kind of hand-out. Every kind is two steps: choose the contacts, then the coordinators.
enum AssignStep { start, who, calls, from, coordinators }

List<AssignStep> stepsFor(AssignKind? k, {bool reassign = false}) => switch (k) {
  null => const [AssignStep.start],
  AssignKind.move when reassign => const [AssignStep.coordinators],
  AssignKind.assign => const [AssignStep.start, AssignStep.who, AssignStep.coordinators],
  AssignKind.followup => const [AssignStep.start, AssignStep.calls, AssignStep.coordinators],
  AssignKind.move => const [AssignStep.start, AssignStep.from, AssignStep.coordinators],
};

/// Splits the plan's contact list into writes of at most [size] contacts per coordinator.
List<Map<String, dynamic>> makeBatches(Map<String, dynamic> plan, {int size = 50}) {
  final out = <Map<String, dynamic>>[];
  for (final m in (plan['moves'] as List)) {
    final persons = [for (final p in (m['persons'] as List)) '$p'];
    for (var i = 0; i < persons.length; i += size) {
      out.add({'coordinator': m['coordinator'], 'persons': persons.sublist(i, i + size > persons.length ? persons.length : i + size)});
    }
  }
  return out;
}
