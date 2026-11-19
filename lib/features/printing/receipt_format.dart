/// The fields an admin can put in the receipt text; the app replaces each one when it prints.
const kReceiptFields = <({String key, String label})>[
  (key: 'name', label: 'Name'),
  (key: 'phone', label: 'Phone'),
  (key: 'event', label: 'Event'),
  (key: 'date', label: 'Date'),
  (key: 'time', label: 'Time'),
  (key: 'count', label: 'Times attended'),
  (key: 'marked_by', label: 'Marked by'),
];

/// What the attendance receipt shows. Set by an admin (Admin → Settings), shared by every phone.
///
/// The receipt is free text, one printed line per typed line. Write a field in curly brackets, for example `{name}`.
/// A line starting with `# ` is printed big and bold, `## ` bold, `~ ` centred, and `---` draws a dotted line.
/// A line whose fields are all empty (for example `Phone: {phone}` for someone with no phone) is left out.
class ReceiptFormat {
  const ReceiptFormat({this.text = '', this.showLogo = true, this.title = 'FOLK', this.subtitle = 'Attendance Receipt', this.footer = 'Hare Krishna!',
    this.showEvent = true, this.showPhone = true, this.showTime = true, this.showCount = true, this.showMarkedBy = false});

  /// The typed receipt. Empty = use [layout] built from the older settings below.
  final String text;
  final bool showLogo;

  // Older settings, kept so a receipt saved before the free-text editor looks the same.
  final String title, subtitle, footer;
  final bool showEvent, showPhone, showTime, showCount, showMarkedBy;

  /// The text that is really printed.
  String get layout => text.trim().isNotEmpty ? text : _legacyLayout();

  String _legacyLayout() => [
    if (showEvent) '## {event}',
    if (subtitle.trim().isNotEmpty) '~ $subtitle',
    '---',
    '# {name}',
    if (showPhone) 'Phone: {phone}',
    if (showTime) ...['Date: {date}', 'Time: {time}'],
    if (showCount) 'Attended: {count}',
    if (showMarkedBy) 'Marked by: {marked_by}',
    if (footer.trim().isNotEmpty) ...['---', '## $footer'],
  ].join('\n');

  factory ReceiptFormat.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const ReceiptFormat();
    const d = ReceiptFormat();
    return ReceiptFormat(
      text: j['text'] as String? ?? d.text,
      showLogo: j['show_logo'] as bool? ?? d.showLogo,
      title: j['title'] as String? ?? d.title,
      subtitle: j['subtitle'] as String? ?? d.subtitle,
      footer: j['footer'] as String? ?? d.footer,
      showEvent: j['show_event'] as bool? ?? d.showEvent,
      showPhone: j['show_phone'] as bool? ?? d.showPhone,
      showTime: j['show_time'] as bool? ?? d.showTime,
      showCount: j['show_count'] as bool? ?? d.showCount,
      showMarkedBy: j['show_marked_by'] as bool? ?? d.showMarkedBy,
    );
  }

  /// What the editor saves: the typed text and the logo switch (the older values are left as they are on the server).
  Map<String, dynamic> toJson() => {'text': text, 'show_logo': showLogo};
}

/// The facts printed on one receipt.
class ReceiptData {
  const ReceiptData({required this.name, required this.mob, required this.event, required this.ts, required this.count, this.markedBy = ''});
  final String name, mob, event, markedBy;

  /// "YYYY-MM-DD HH:mm:ss" (India time).
  final String ts;

  /// How many times this person has attended, including today.
  final int count;
}
