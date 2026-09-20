import 'package:latlong2/latlong.dart' show LatLng;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/platform/maps/offline_catalog.dart';
import '../../../core/platform/maps/offline_map_service.dart';

/// What to offer a person who is in [region] and is missing some of its maps.
class MapOffer {
  const MapOffer({required this.region, required this.packs});

  final OfflineRegion region;

  /// The maps worth having here that are not on the phone, the city they are in
  /// first and the wider overview after it.
  final List<OfflinePack> packs;

  int get bytes => packs.fold(0, (sum, p) => sum + p.approxBytes);

  /// The city (or main area) named in the offer's heading.
  OfflinePack get headline => packs.first;
}

/// Decides when to ask "want offline maps for where you are?".
///
/// It asks at most once per region until the answer changes: "Not now" waits a
/// few days, "Don't ask again" is forever. Nothing is ever downloaded by this
/// class - it only decides whether to offer.
class MapDownloadPrompter {
  MapDownloadPrompter({
    required this.maps,
    DateTime Function()? clock,
    this.snooze = const Duration(days: 3),
  }) : _clock = clock ?? DateTime.now;

  final OfflineMapService maps;
  final DateTime Function() _clock;

  /// How long "Not now" holds the question back.
  final Duration snooze;

  static String _neverKey(OfflineRegion r) => 'map_prompt_never_${r.id}';
  static String _snoozeKey(OfflineRegion r) => 'map_prompt_snoozed_at_${r.id}';

  /// The region whose box contains [point], or null.
  static OfflineRegion? regionAt(LatLng point) {
    for (final region in OfflineCatalog.regions) {
      if (region.packs.any((p) => p.contains(point))) return region;
    }
    return null;
  }

  /// What to offer at [point], or null when there is nothing to offer: outside
  /// every region, everything already on the phone, or the person said no.
  Future<MapOffer?> offerAt(LatLng point) async {
    final region = regionAt(point);
    if (region == null) return null;

    final missing = [
      for (final pack in region.packs)
        if (pack.contains(point) && !maps.isInstalled(pack.id)) pack,
    ];
    if (missing.isEmpty) return null;

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_neverKey(region)) ?? false) return null;
    final snoozedAt = prefs.getInt(_snoozeKey(region));
    if (snoozedAt != null &&
        _clock().difference(DateTime.fromMillisecondsSinceEpoch(snoozedAt)) <
            snooze) {
      return null;
    }

    // The city first: it is the small one and the one being driven in.
    missing.sort((a, b) => (a.detail ? 0 : 1).compareTo(b.detail ? 0 : 1));
    return MapOffer(region: region, packs: missing);
  }

  /// "Not now": ask again after [snooze].
  Future<void> notNow(OfflineRegion region) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_snoozeKey(region), _clock().millisecondsSinceEpoch);
  }

  /// "Don't ask again" for this region.
  Future<void> neverAsk(OfflineRegion region) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_neverKey(region), true);
  }
}
