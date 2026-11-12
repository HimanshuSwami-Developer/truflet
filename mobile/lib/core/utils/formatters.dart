/// Indian-grouped rupees: 125000 → ₹1,25,000.
String inr(num? n) {
  final v = (n ?? 0).round();
  final s = v.abs().toString();
  if (s.length <= 3) return '${v < 0 ? '-' : ''}₹$s';
  final last3 = s.substring(s.length - 3);
  var rest = s.substring(0, s.length - 3);
  final parts = <String>[];
  while (rest.length > 2) {
    parts.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) parts.insert(0, rest);
  return '${v < 0 ? '-' : ''}₹${parts.join(',')},$last3';
}

String fmtHour(int h) => '${(h % 12) == 0 ? 12 : h % 12} ${h % 24 < 12 ? 'AM' : 'PM'}';
String fmtTime(int h) => '${(h % 12) == 0 ? 12 : h % 12}:00 ${h % 24 < 12 ? 'AM' : 'PM'}';
