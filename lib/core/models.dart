import '../features/printing/receipt_format.dart';

class Person {
  const Person({
    required this.mob,
    required this.name,
    this.id = '',
    this.gender = '',
    this.level = '',
    this.occupation = '',
    this.profession = '',
    this.pgName = '',
    this.eventCode = '',
    this.tag = 'Public',
    this.isActive = true,
    this.attendanceCount = 0,
    this.lastAttendedOn = '',
    this.registeredBy = '',
    this.joined = '',
    this.venue = '',
    this.gmapLink = '',
    this.callNo = '',
    this.fgName = '',
    this.fgMob = '',
    this.folkGuide = '',
    this.age = 0,
    this.currentStay = '',
    this.skills = '',
    this.interests = '',
    this.chantingRounds = 0,
    this.feedback = '',
    this.comments = '',
  });

  final String id, mob, name, gender, level, occupation, profession, pgName, eventCode, tag, lastAttendedOn, registeredBy, joined;
  final String venue, gmapLink, callNo, fgName, fgMob, folkGuide;
  final String currentStay, skills, interests, feedback, comments;
  final bool isActive;
  final int attendanceCount, age, chantingRounds;

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
    pgName: j['pg_name'] as String? ?? '',
    eventCode: j['event_code'] as String? ?? '',
    tag: j['tag'] as String? ?? 'Public',
    isActive: j['is_active'] as bool? ?? true,
    attendanceCount: (j['attendance_count'] as num?)?.toInt() ?? 0,
    lastAttendedOn: j['last_attended_on'] as String? ?? '',
    registeredBy: j['registered_by'] as String? ?? '',
    joined: j['joined'] as String? ?? '',
    venue: j['venue'] as String? ?? '',
    gmapLink: j['gmap_link'] as String? ?? '',
    callNo: j['call_no'] as String? ?? '',
    fgName: j['fg_name'] as String? ?? '',
    fgMob: j['fg_mob'] as String? ?? '',
    folkGuide: j['folk_guide'] as String? ?? '',
    age: (j['age'] as num?)?.toInt() ?? 0,
    currentStay: j['current_stay'] as String? ?? '',
    skills: j['skills'] as String? ?? '',
    interests: j['interests'] as String? ?? '',
    chantingRounds: (j['chanting_rounds'] as num?)?.toInt() ?? 0,
    feedback: j['feedback'] as String? ?? '',
    comments: j['comments'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'mob': mob,
    'name': name,
    'gender': gender,
    'level': level,
    'occupation': occupation,
    'profession': profession,
    'pg_name': pgName,
    'event_code': eventCode,
    'tag': tag,
    'is_active': isActive,
    'attendance_count': attendanceCount,
    'last_attended_on': lastAttendedOn,
    'registered_by': registeredBy,
    'joined': joined,
    'venue': venue,
    'gmap_link': gmapLink,
    'call_no': callNo,
    'fg_name': fgName,
    'fg_mob': fgMob,
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
