/// Formatting helpers for a planned journey: distance, duration and arrival
/// clock time. No `intl` dependency (not a declared package here) — plain
/// arithmetic is enough for these shapes.

/// "850 m" under ~950 m, otherwise "12.4 km" (no decimal past 10 km).
String formatRouteDistance(double meters) {
  if (meters < 950) return '${meters.round()} m';
  final km = meters / 1000;
  return '${km.toStringAsFixed(km < 10 ? 1 : 0)} km';
}

/// "24 min", or "1 h 05 min" past an hour.
String formatRouteDuration(double seconds) {
  final totalMinutes = (seconds / 60).round();
  if (totalMinutes < 60) return '$totalMinutes min';
  final h = totalMinutes ~/ 60;
  final m = totalMinutes % 60;
  return m == 0 ? '$h h' : '$h h ${m.toString().padLeft(2, '0')} min';
}

/// "2:45 PM" style wall-clock time.
String formatArrivalClock(DateTime at) {
  final minute = at.minute.toString().padLeft(2, '0');
  final period = at.hour >= 12 ? 'PM' : 'AM';
  var hour12 = at.hour % 12;
  if (hour12 == 0) hour12 = 12;
  return '$hour12:$minute $period';
}

/// The clock time [remainingSeconds] from now, given the current instant.
String formatArrivalIn(double remainingSeconds, DateTime now) =>
    formatArrivalClock(now.add(Duration(seconds: remainingSeconds.round())));
