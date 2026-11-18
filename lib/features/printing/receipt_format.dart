/// What the attendance receipt shows. Set by an admin (Admin → Settings), shared by every phone.
class ReceiptFormat {
  const ReceiptFormat({
    this.title = 'FOLK',
    this.subtitle = 'Attendance Receipt',
    this.footer = 'Hare Krishna!',
    this.showEvent = true,
    this.showPhone = true,
    this.showTime = true,
    this.showCount = true,
    this.showMarkedBy = false,
  });

  final String title, subtitle, footer;
  final bool showEvent, showPhone, showTime, showCount, showMarkedBy;

  factory ReceiptFormat.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const ReceiptFormat();
    const d = ReceiptFormat();
    return ReceiptFormat(
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

  Map<String, dynamic> toJson() => {
    'title': title,
    'subtitle': subtitle,
    'footer': footer,
    'show_event': showEvent,
    'show_phone': showPhone,
    'show_time': showTime,
    'show_count': showCount,
    'show_marked_by': showMarkedBy,
  };
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
