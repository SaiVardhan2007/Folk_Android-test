/// Time in India (the programme runs in Hyderabad), independent of the phone's own time zone.
DateTime istNow() => DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));

String _two(int n) => n.toString().padLeft(2, '0');

/// "2026-11-16"
String istDate([DateTime? d]) {
  final t = d ?? istNow();
  return '${t.year}-${_two(t.month)}-${_two(t.day)}';
}

/// "2026-11-16 13:05:09" (the format the API expects for offline check-ins)
String istTimestamp([DateTime? d]) {
  final t = d ?? istNow();
  return '${istDate(t)} ${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';
}

/// "1:05 PM" from an ERPNext "YYYY-MM-DD HH:mm:ss" string.
String shortTime(String ts) {
  if (ts.length < 16) return ts;
  final h = int.tryParse(ts.substring(11, 13)) ?? 0;
  final m = ts.substring(14, 16);
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12:$m ${h >= 12 ? 'PM' : 'AM'}';
}

/// Returns the 10-digit Indian mobile number inside [raw] (handles +91, spaces, dashes, QR text), or null.
String? normalizeMobile(String raw) {
  var d = raw.replaceAll(RegExp(r'\D'), '');
  if (d.length == 12 && d.startsWith('91')) d = d.substring(2);
  if (d.length == 11 && d.startsWith('0')) d = d.substring(1);
  return RegExp(r'^\d{10}$').hasMatch(d) ? d : null;
}

String firstName(String name) => name.trim().split(RegExp(r'\s+')).first;
