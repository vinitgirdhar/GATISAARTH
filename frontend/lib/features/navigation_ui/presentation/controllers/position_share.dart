/// The text a driver sends when they share where they are: the last trusted
/// position, how uncertain it is, and whether it comes from dead reckoning.
///
/// Never a bare pin: an ambulance or a fleet desk needs the radius and the time
/// since GNSS was lost to judge how far to trust it.
String positionShareText({
  required double latitude,
  required double longitude,
  required double? marginM,
  required bool deadReckoning,
  required Duration sinceGnssLost,
  required DateTime at,
}) {
  final lat = latitude.toStringAsFixed(5), lon = longitude.toStringAsFixed(5);
  final radius = marginM == null ? 'uncertainty unknown' : '± ${marginM.round()} m';
  final hh = at.hour.toString().padLeft(2, '0');
  final mm = at.minute.toString().padLeft(2, '0');
  final source = deadReckoning
      ? 'dead reckoning, GNSS lost ${_duration(sinceGnssLost)} ago'
      : 'live GNSS fix';
  return 'My position at $hh:$mm: $lat, $lon ($radius, $source).\n'
      'https://www.openstreetmap.org/?mlat=$lat&mlon=$lon#map=17/$lat/$lon\n'
      'Sent from GatiSaarth.';
}

String _duration(Duration d) {
  final s = d.inSeconds;
  if (s < 60) return '$s s';
  final m = d.inMinutes;
  return s % 60 == 0 ? '$m min' : '$m min ${s % 60} s';
}
