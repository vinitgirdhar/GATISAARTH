/// Human-readable coordinates with the correct hemisphere letter
/// (e.g. `37.4220°N`, `122.0840°W`) — never a signed number plus a fixed
/// letter.
String formatLatitude(double degrees, {int digits = 4}) =>
    '${degrees.abs().toStringAsFixed(digits)}°${degrees >= 0 ? 'N' : 'S'}';

String formatLongitude(double degrees, {int digits = 4}) =>
    '${degrees.abs().toStringAsFixed(digits)}°${degrees >= 0 ? 'E' : 'W'}';

/// Short "lat, lon" pair for a picked point, e.g. "28.6390°N, 77.0661°E".
String formatCoordinates(double lat, double lon, {int digits = 4}) =>
    '${formatLatitude(lat, digits: digits)}, ${formatLongitude(lon, digits: digits)}';
