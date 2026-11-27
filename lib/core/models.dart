import '../features/printing/receipt_format.dart';

/// One value of a dropdown list (College / Company, Branch, Skill, Interest). People store the [id]; the [title] can be edited in
/// ERPNext and then shows everywhere. An empty [id] with a [title] means typed text that is not in the list yet (the server adds it).
class Opt {
  const Opt(this.id, this.title);
  static const none = Opt('', '');
  final String id, title;
  bool get isEmpty => id.isEmpty && title.isEmpty;
  factory Opt.fromJson(Map<String, dynamic> j) => Opt(j['id'] as String? ?? '', j['title'] as String? ?? '');
  Map<String, dynamic> toJson() => {'id': id, 'title': title};
  @override
  bool operator ==(Object other) => other is Opt && other.id == id && other.title == title;
  @override
  int get hashCode => Object.hash(id, title);
}

/// Same rule as the server: two titles are the same value when they differ only in case, spaces or punctuation ("C.B.I.T" = "CBIT").
String optKey(String s) => s.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');

List<Opt> _opts(Object? v) => ((v as List?) ?? const []).map((e) => Opt.fromJson(Map<String, dynamic>.from(e as Map))).toList();

/// The dropdown lists stored by ID on the server. [OptionList.name] is the list's name in the API (/options/college).
enum OptionList { college, branch, skill, interest, pg, area }

/// A FOLK Guide: name in capitals (e.g. VKGD) and the guide's phone, which belongs to the guide, not to each person.
/// Guides are added only in ERPNext (the app has no Add button for them).
class Guide extends Opt {
  const Guide(super.id, super.title, {this.mobile = '', this.isDefault = false});
  final String mobile;

  /// Picked for a new person unless someone chooses another guide.
  final bool isDefault;
  factory Guide.fromJson(Map<String, dynamic> j) => Guide(
    j['id'] as String? ?? '',
    j['title'] as String? ?? '',
    mobile: j['mobile'] as String? ?? '',
    isDefault: j['is_default'] as bool? ?? false,
  );
}

class OptionLists {
  const OptionLists([this.lists = const {}, this.guides = const []]);
  final Map<OptionList, List<Opt>> lists;
  final List<Guide> guides;
  List<Opt> operator [](OptionList l) => lists[l] ?? const [];

  /// The guide given to new people (the one marked default in ERPNext, else the only one).
  Guide? get defaultGuide => guides.where((g) => g.isDefault).firstOrNull ?? (guides.length == 1 ? guides.first : null);

  factory OptionLists.fromJson(Map<String, dynamic> j) => OptionLists({
    for (final l in OptionList.values) l: _opts(j[l.name]),
  }, ((j['guide'] as List?) ?? const []).map((e) => Guide.fromJson(Map<String, dynamic>.from(e as Map))).toList());
}

class Person {
  const Person({
    required this.mob,
    required this.name,
    this.id = '',
    this.gender = '',
    this.level = '',
    this.occupation = '',
    this.profession = '',
    this.collegeId = '',
    this.branch = '',
    this.branchId = '',
    this.skillList = const [],
    this.interestList = const [],
    this.pgName = '',
    this.pgId = '',
    this.areaName = '',
    this.areaId = '',
    this.dob = '',
    this.eventCode = '',
    this.tag = 'Public',
    this.isActive = true,
    this.attendanceCount = 0,
    this.lastAttendedOn = '',
    this.registeredBy = '',
    this.joined = '',
    this.venue = '',
    this.guide = '',
    this.guideId = '',
    this.guideMobile = '',
    this.age = 0,
    this.currentStay = '',
    this.skills = '',
    this.interests = '',
    this.chantingRounds = 0,
    this.feedback = '',
    this.comments = '',
    this.callsCount = 0,
  });

  /// [profession] is the College / Company title (its ID is [collegeId]); [skills] and [interests] are the titles joined by commas.
  final String id,
      mob,
      name,
      gender,
      level,
      occupation,
      profession,
      collegeId,
      branch,
      branchId,
      pgName,
      pgId,
      areaName,
      areaId,
      eventCode,
      tag,
      lastAttendedOn,
      registeredBy,
      joined;
  final String venue;

  /// Date of birth "YYYY-MM-DD" ('' = not given). [age] is worked out from it by the server (or is the age typed before dates of birth were asked).
  final String dob;

  /// FOLK guide: name (capitals), its ID in the guide list, and the guide's phone.
  final String guide, guideId, guideMobile;
  final String currentStay, skills, interests, feedback, comments;
  final List<Opt> skillList, interestList;
  final bool isActive;
  final int attendanceCount, age, chantingRounds;

  /// Calls made to this person (only filled in by the admin People list).
  final int callsCount;

  bool get isAdmin => tag == 'Admin';
  bool get isCoordinator => tag == 'Coordinator';
  bool get isStaff => tag == 'Admin' || tag == 'Coordinator';

  /// A contact, not an app user. Only Public contacts are offered for calling.
  bool get isContact => tag == 'Public' || tag == 'Not Interested';

  /// Signed up in the app but not yet approved by an admin.
  bool get isPending => !isActive && !isContact && registeredBy == 'self sign-up';

  factory Person.fromJson(Map<String, dynamic> j) => Person(
    id: j['id'] as String? ?? '',
    mob: j['mob'] as String? ?? '',
    name: j['name'] as String? ?? '',
    gender: j['gender'] as String? ?? '',
    level: j['level'] as String? ?? '',
    occupation: j['occupation'] as String? ?? '',
    profession: j['profession'] as String? ?? '',
    collegeId: j['college_id'] as String? ?? '',
    branch: j['branch'] as String? ?? '',
    branchId: j['branch_id'] as String? ?? '',
    skillList: _opts(j['skill_list']),
    interestList: _opts(j['interest_list']),
    pgName: j['pg_name'] as String? ?? '',
    pgId: j['pg_id'] as String? ?? '',
    areaName: j['area_name'] as String? ?? '',
    areaId: j['area_id'] as String? ?? '',
    dob: j['dob'] as String? ?? '',
    eventCode: j['event_code'] as String? ?? '',
    tag: j['tag'] as String? ?? 'Public',
    isActive: j['is_active'] as bool? ?? true,
    attendanceCount: (j['attendance_count'] as num?)?.toInt() ?? 0,
    lastAttendedOn: j['last_attended_on'] as String? ?? '',
    registeredBy: j['registered_by'] as String? ?? '',
    joined: j['joined'] as String? ?? '',
    venue: j['venue'] as String? ?? '',
    guide: j['guide'] as String? ?? '',
    guideId: j['guide_id'] as String? ?? '',
    guideMobile: j['guide_mobile'] as String? ?? '',
    age: (j['age'] as num?)?.toInt() ?? 0,
    currentStay: j['current_stay'] as String? ?? '',
    skills: j['skills'] as String? ?? '',
    interests: j['interests'] as String? ?? '',
    chantingRounds: (j['chanting_rounds'] as num?)?.toInt() ?? 0,
    feedback: j['feedback'] as String? ?? '',
    comments: j['comments'] as String? ?? '',
    callsCount: (j['calls_count'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'mob': mob,
    'name': name,
    'gender': gender,
    'level': level,
    'occupation': occupation,
    'profession': profession,
    'college_id': collegeId,
    'branch': branch,
    'branch_id': branchId,
    'skill_list': [for (final o in skillList) o.toJson()],
    'interest_list': [for (final o in interestList) o.toJson()],
    'pg_name': pgName,
    'pg_id': pgId,
    'area_name': areaName,
    'area_id': areaId,
    'dob': dob,
    'event_code': eventCode,
    'tag': tag,
    'is_active': isActive,
    'attendance_count': attendanceCount,
    'last_attended_on': lastAttendedOn,
    'registered_by': registeredBy,
    'joined': joined,
    'venue': venue,
    'guide': guide,
    'guide_id': guideId,
    'guide_mobile': guideMobile,
    'age': age,
    'current_stay': currentStay,
    'skills': skills,
    'interests': interests,
    'chanting_rounds': chantingRounds,
    'feedback': feedback,
    'comments': comments,
  };
}

class FolkEvent {
  const FolkEvent(this.code, this.name, this.isCurrent);
  final String code, name;
  final bool isCurrent;
  factory FolkEvent.fromJson(Map<String, dynamic> j) =>
      FolkEvent(j['code'] as String, j['name'] as String? ?? j['code'] as String, j['is_current'] as bool? ?? false);
  Map<String, dynamic> toJson() => {'code': code, 'name': name, 'is_current': isCurrent};
}

/// Everything the app needs at start-up (one API call, cached for offline use).
class Bootstrap {
  const Bootstrap({
    required this.user,
    required this.events,
    this.lists = const [],
    required this.currentEvent,
    required this.tags,
    required this.levels,
    required this.genders,
    required this.occupations,
    this.stays = const ['With Parents', 'In Hostel'],
    this.feedbacks = const ['Excellent', 'Good'],
    this.offlineEnabled = false,
    this.receipt = const ReceiptFormat(),
  });
  final Person user;
  final List<FolkEvent> events;

  /// Always-open contact lists (Feedback, Contacts Register). Not events: never "current", no attendance days.
  final List<FolkEvent> lists;

  /// Events plus lists, for filters and call assignment where either can apply.
  List<FolkEvent> get eventsAndLists => [...events, ...lists];
  final String currentEvent;
  final List<String> tags, levels, genders, occupations, stays, feedbacks;

  /// Admin switch (Admin → Settings): lets check-ins be saved on the phone when there is no signal.
  final bool offlineEnabled;

  /// What the printed attendance receipt shows (Admin → Settings → Receipt format).
  final ReceiptFormat receipt;

  factory Bootstrap.fromJson(Map<String, dynamic> j) {
    List<String> list(String k) => ((j[k] as List?) ?? const []).map((e) => e.toString()).toList();
    return Bootstrap(
      user: Person.fromJson(Map<String, dynamic>.from(j['user'] as Map)),
      events: ((j['events'] as List?) ?? const []).map((e) => FolkEvent.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      lists: ((j['lists'] as List?) ?? const []).map((e) => FolkEvent.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      currentEvent: j['current_event'] as String? ?? '',
      tags: list('tags'),
      levels: list('levels'),
      genders: list('genders'),
      occupations: list('occupations'),
      stays: list('stays'),
      feedbacks: list('feedbacks'),
      offlineEnabled: ((j['settings'] as Map?)?['offline_queue_enabled'] as bool?) ?? false,
      receipt: ReceiptFormat.fromJson(((j['settings'] as Map?)?['receipt'] as Map?)?.cast<String, dynamic>()),
    );
  }
}

class AttendanceItem {
  const AttendanceItem({
    required this.id,
    required this.mob,
    required this.name,
    required this.markedBy,
    required this.markedByMob,
    required this.ts,
  });
  final String id, mob, name, markedBy, markedByMob, ts;
  factory AttendanceItem.fromJson(Map<String, dynamic> j) => AttendanceItem(
    id: j['id'] as String,
    mob: j['mob'] as String? ?? '',
    name: j['name'] as String? ?? '',
    markedBy: j['marked_by'] as String? ?? '',
    markedByMob: j['marked_by_mob'] as String? ?? '',
    ts: j['ts'] as String? ?? '',
  );
}

String genderLabel(String g) => g == 'M'
    ? 'Male'
    : g == 'F'
    ? 'Female'
    : '';
