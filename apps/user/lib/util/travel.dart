/// Travel-time estimate from a straight-line distance (km): road factor 1.35, city / highway average speeds.
int travelMinutes(double km) {
  if (km <= 0) return 0;
  final road = km * 1.35;
  final speed = road <= 15 ? 22.0 : (road <= 150 ? 42.0 : 55.0);
  return (road / speed * 60).ceil().clamp(1, 3000);
}

String fmtMinutes(int minutes) {
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60;
  final r = minutes % 60;
  return r == 0 ? '$h h' : '$h h $r min';
}

String fmtClock(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final m = t.minute.toString().padLeft(2, '0');
  return '$h:$m ${t.hour >= 12 ? 'PM' : 'AM'}';
}

/// "About 45 min away - arrive by 3:20 PM if you leave now" (empty when the distance is unknown).
String etaLine(dynamic km, num Function(dynamic) toNum) {
  if (km == null) return '';
  final d = toNum(km).toDouble();
  if (d <= 0) return '';
  final m = travelMinutes(d);
  return 'About ${fmtMinutes(m)} away - arrive by ${fmtClock(DateTime.now().add(Duration(minutes: m)))} if you leave now';
}
