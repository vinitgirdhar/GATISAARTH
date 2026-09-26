import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/nav/route/planned_route.dart' show ManeuverKind;
import '../../../core/platform/maps/place_search.dart';
import '../../../core/theme/app_theme.dart';
import '../../navigation_ui/presentation/controllers/live_session_scope.dart';
import '../application/journey_service.dart';
import '../domain/journey.dart';
import 'journey_format.dart';
import 'place_picker_screen.dart';
import 'widgets/planner_backdrop_map.dart';
import 'widgets/route_preview_map.dart';

enum _Field { from, to }

/// Google-Maps-like journey planner: From/To search over the offline map
/// packs, a plan-in-progress stage readout, and a route preview with Start.
///
/// Degrades to a plain "unavailable" message when no [JourneyScope] is above
/// this context — this screen is only pushed from places that already
/// checked that, but the contract asks every journey screen to cope anyway.
class RoutePlannerScreen extends StatefulWidget {
  const RoutePlannerScreen({super.key, this.focusTo = true});

  /// Focuses the To field on open — the common case from Home.
  final bool focusTo;

  @override
  State<RoutePlannerScreen> createState() => _RoutePlannerScreenState();
}

class _RoutePlannerScreenState extends State<RoutePlannerScreen> {
  static const _yourLocation = JourneyPlace(
    name: 'Your location',
    lat: 0,
    lon: 0,
    isCurrentLocation: true,
  );

  final _fromController = TextEditingController(text: 'Your location');
  final _toController = TextEditingController();
  final _fromFocus = FocusNode();
  final _toFocus = FocusNode();

  JourneyPlace? _from = _yourLocation;
  JourneyPlace? _to;
  JourneyPlace? _lastPlannedFrom;
  JourneyPlace? _lastPlannedTo;

  /// Sticky: which field a search/quick-action targets. Unlike "currently
  /// focused", this survives the focus loss a button tap causes just before
  /// its onPressed runs.
  _Field? _lastFocusedField;
  bool _editing = false;

  List<PlaceResult> _results = const [];
  bool _searching = false;
  Timer? _debounce;
  int _searchToken = 0;

  @override
  void initState() {
    super.initState();
    _fromFocus.addListener(_onFocusChanged);
    _toFocus.addListener(_onFocusChanged);
    if (widget.focusTo) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _toFocus.requestFocus());
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _fromController.dispose();
    _toController.dispose();
    _fromFocus.dispose();
    _toFocus.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    final active = _fromFocus.hasFocus
        ? _Field.from
        : _toFocus.hasFocus
            ? _Field.to
            : null;
    setState(() {
      _editing = active != null;
      if (active != null) {
        _lastFocusedField = active;
        _results = const [];
      }
    });
  }

  void _onQueryChanged(String query, JourneyService? journey) {
    _debounce?.cancel();
    if (journey == null || query.trim().isEmpty) {
      setState(() => _results = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      if (!mounted) return;
      final token = ++_searchToken;
      final session = LiveSessionScope.of(context);
      setState(() => _searching = true);
      final results = await journey.places.search(
        query,
        nearLat: session.latitude,
        nearLon: session.longitude,
      );
      if (!mounted || token != _searchToken) return;
      setState(() {
        _results = results;
        _searching = false;
      });
    });
  }

  void _select(JourneyPlace place, JourneyService? journey) {
    final field = _lastFocusedField ?? _Field.to;
    setState(() {
      if (field == _Field.from) {
        _from = place;
        _fromController.text = place.name;
      } else {
        _to = place;
        _toController.text = place.name;
      }
      _results = const [];
    });
    FocusScope.of(context).unfocus();
    _maybePlan(journey);
  }

  void _swap() {
    setState(() {
      final f = _from;
      _from = _to;
      _to = f;
      _fromController.text = _from?.name ?? '';
      _toController.text = _to?.name ?? '';
    });
    _maybePlan(JourneyScope.maybeOf(context));
  }

  void _useYourLocation(JourneyService? journey) =>
      _select(_yourLocation, journey);

  Future<void> _chooseOnMap(JourneyService? journey) async {
    final pickingFrom = _lastFocusedField == _Field.from;
    final place = await Navigator.of(context).push<JourneyPlace>(
      MaterialPageRoute(
        builder: (_) => PlacePickerScreen(pickingFrom: pickingFrom),
      ),
    );
    if (place == null || !mounted) return;
    _select(place, journey);
  }

  void _maybePlan(JourneyService? journey) {
    final from = _from;
    final to = _to;
    if (journey == null || from == null || to == null) return;
    if (from == _lastPlannedFrom && to == _lastPlannedTo) return;
    _lastPlannedFrom = from;
    _lastPlannedTo = to;
    journey.plan(from: from, to: to);
  }

  void _retry(JourneyService? journey) {
    final from = _from;
    final to = _to;
    if (journey == null || from == null || to == null) return;
    journey.plan(from: from, to: to);
  }

  Future<void> _start(JourneyService journey, Journey preview) async {
    await journey.start(preview);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final journey = JourneyScope.maybeOf(context);
    final session = LiveSessionScope.of(context);

    // While choosing places the map of where you are sits behind everything
    // (maps-app style); once a route is being planned or previewed the page
    // goes back to a plain surface so the summary reads cleanly.
    final overMap = journey != null && _editing;
    return Scaffold(
      extendBodyBehindAppBar: overMap,
      appBar: AppBar(
        title: const Text('Plan a journey'),
        backgroundColor: overMap ? Colors.transparent : null,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: overMap
            ? Padding(
                padding: const EdgeInsets.all(6),
                child:
                    _MapChip(child: BackButton(color: AppColors.textPrimary)),
              )
            : null,
        flexibleSpace: overMap
            ? IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Theme.of(context).scaffoldBackgroundColor,
                        Theme.of(context)
                            .scaffoldBackgroundColor
                            .withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              )
            : null,
      ),
      body: journey == null
          ? const _Unavailable()
          : Stack(
              children: [
                if (overMap) const Positioned.fill(child: PlannerBackdropMap()),
                SafeArea(
                  child: Column(
                    children: [
                      _FieldsCard(
                        fromController: _fromController,
                        toController: _toController,
                        fromFocus: _fromFocus,
                        toFocus: _toFocus,
                        onChanged: (text) => _onQueryChanged(text, journey),
                        onSwap: _swap,
                      ),
                      if (_editing)
                        _FloatingCard(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _QuickOption(
                                icon: Icons.my_location_rounded,
                                label: 'Your location',
                                enabled: session.uncertainty != null,
                                hint: 'Waiting for a GPS fix',
                                onTap: () => _useYourLocation(journey),
                              ),
                              _QuickOption(
                                icon: Icons.map_rounded,
                                label: 'Choose on map',
                                enabled: true,
                                onTap: () => _chooseOnMap(journey),
                              ),
                            ],
                          ),
                        ),
                      Expanded(
                        child: _editing
                            ? _SearchResults(
                                results: _results,
                                searching: _searching,
                                hasQuery: (_lastFocusedField == _Field.from
                                        ? _fromController
                                        : _toController)
                                    .text
                                    .trim()
                                    .isNotEmpty,
                                onSelect: (r) => _select(
                                  JourneyPlace(
                                      name: r.name, lat: r.lat, lon: r.lon),
                                  journey,
                                ),
                              )
                            : _PlanStatus(
                                journey: journey,
                                onRetry: () => _retry(journey),
                                onStart: (preview) => _start(journey, preview),
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _FieldsCard extends StatelessWidget {
  const _FieldsCard({
    required this.fromController,
    required this.toController,
    required this.fromFocus,
    required this.toFocus,
    required this.onChanged,
    required this.onSwap,
  });

  final TextEditingController fromController;
  final TextEditingController toController;
  final FocusNode fromFocus;
  final FocusNode toFocus;
  final ValueChanged<String> onChanged;
  final VoidCallback onSwap;

  Widget _field(
    IconData icon,
    TextEditingController controller,
    FocusNode focus,
    String hint,
    Key key,
  ) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            key: key,
            controller: controller,
            focusNode: focus,
            onChanged: onChanged,
            decoration: InputDecoration(
              hintText: hint,
              border: InputBorder.none,
              isDense: true,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(AppSpacing.md),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.cardRadius,
        boxShadow: AppShadow.card,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                _field(Icons.my_location_rounded, fromController, fromFocus,
                    'Your location', const ValueKey('journey-from-field')),
                Divider(color: AppColors.surfaceBorder, height: 1),
                _field(Icons.place_rounded, toController, toFocus,
                    'Choose destination', const ValueKey('journey-to-field')),
              ],
            ),
          ),
          Semantics(
            button: true,
            label: 'Swap from and to',
            excludeSemantics: true,
            child: IconButton(
              icon: const Icon(Icons.swap_vert_rounded),
              onPressed: onSwap,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickOption extends StatelessWidget {
  const _QuickOption({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
    this.hint,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading:
          Icon(icon, color: enabled ? AppColors.primary : AppColors.disabled),
      title: Text(
        label,
        style: TextStyle(
          color: enabled ? AppColors.textPrimary : AppColors.textMuted,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: enabled || hint == null ? null : Text(hint!),
      onTap: enabled ? onTap : null,
    );
  }
}

class _SearchResults extends StatelessWidget {
  const _SearchResults({
    required this.results,
    required this.searching,
    required this.hasQuery,
    required this.onSelect,
  });

  final List<PlaceResult> results;
  final bool searching;
  final bool hasQuery;
  final ValueChanged<PlaceResult> onSelect;

  static IconData _iconFor(String kind) {
    final k = kind.toLowerCase();
    if (k.contains('hospital')) return Icons.local_hospital_rounded;
    if (k.contains('station')) return Icons.train_rounded;
    if (k.contains('road')) return Icons.add_road_rounded;
    if (k.contains('locality') || k.contains('neighbourhood')) {
      return Icons.location_city_rounded;
    }
    return Icons.place_rounded;
  }

  @override
  Widget build(BuildContext context) {
    if (searching) {
      return const Center(child: CircularProgressIndicator());
    }
    if (results.isEmpty) {
      if (!hasQuery) return const SizedBox.shrink();
      return Align(
        alignment: Alignment.topCenter,
        child: _FloatingCard(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Text(
              'No results — search only covers the maps installed on this '
              'phone, offline.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ),
      );
    }
    return Align(
      alignment: Alignment.topCenter,
      child: _FloatingCard(
        child: ListView.builder(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: results.length,
          itemBuilder: (context, i) {
            final r = results[i];
            final distance = r.distanceM == null
                ? ''
                : ' · ${formatRouteDistance(r.distanceM!)}';
            return ListTile(
              leading: Icon(_iconFor(r.kind), color: AppColors.primary),
              title: Text(r.name),
              subtitle: Text('${r.kind}$distance'),
              onTap: () => onSelect(r),
            );
          },
        ),
      ),
    );
  }
}

class _PlanStatus extends StatelessWidget {
  const _PlanStatus({
    required this.journey,
    required this.onRetry,
    required this.onStart,
  });

  final JourneyService journey;
  final VoidCallback onRetry;
  final ValueChanged<Journey> onStart;

  static String _stageText(JourneyStage stage, double? progress) =>
      switch (stage) {
        JourneyStage.idle => 'Choose a destination to plan a route',
        JourneyStage.checkingMaps => 'Checking offline maps',
        JourneyStage.downloadingMap => progress == null
            ? 'Downloading map for this route'
            : 'Downloading map for this route · '
                '${(progress * 100).round()}%',
        JourneyStage.readingRoads => 'Reading roads',
        JourneyStage.planning => 'Calculating route',
        JourneyStage.saving => 'Saving journey for offline use',
        JourneyStage.ready => 'Ready',
        JourneyStage.failed => 'Could not plan this route',
      };

  @override
  Widget build(BuildContext context) {
    final stage = journey.stage;
    final preview = journey.preview;

    if (stage == JourneyStage.ready && preview != null) {
      return _PreviewCard(preview: preview, onStart: () => onStart(preview));
    }
    if (stage == JourneyStage.failed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded,
                  color: AppColors.error, size: 32),
              const SizedBox(height: AppSpacing.sm),
              Text(
                journey.error ?? 'Could not plan this route',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.md),
              FilledButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    if (stage == JourneyStage.idle) return const SizedBox.shrink();

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              child: LinearProgressIndicator(
                value: stage == JourneyStage.downloadingMap
                    ? journey.downloadProgress
                    : null,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              _stageText(stage, journey.downloadProgress),
              style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.preview, required this.onStart});

  final Journey preview;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final route = preview.route;
    final turns = route.maneuvers
        .where((m) =>
            m.kind != ManeuverKind.depart && m.kind != ManeuverKind.arrive)
        .length;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        RoutePreviewMap(route: route),
        const SizedBox(height: AppSpacing.md),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _Stat(label: 'DISTANCE', value: formatRouteDistance(route.lengthM)),
            _Stat(label: 'ETA', value: formatRouteDuration(route.durationS)),
            _Stat(label: 'TURNS', value: '$turns'),
            if (route.tunnels.isNotEmpty)
              _Stat(label: 'TUNNELS', value: '${route.tunnels.length}'),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.healthy.withValues(alpha: 0.14),
              borderRadius: AppRadius.pillRadius,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.offline_pin_rounded,
                    size: 16, color: AppColors.healthy),
                const SizedBox(width: 6),
                Text(
                  'Saved for offline use',
                  style: TextStyle(
                    color: AppColors.healthy,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        SizedBox(
          height: 52,
          child: FilledButton.icon(
            onPressed: onStart,
            icon: const Icon(Icons.navigation_rounded),
            label: const Text('Start'),
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );
}

class _Unavailable extends StatelessWidget {
  const _Unavailable();

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Text(
            "Route planning isn't available right now.",
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
}

/// A surface card floating over the backdrop map, same look as the fields.
class _FloatingCard extends StatelessWidget {
  const _FloatingCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(
            AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadius.cardRadius,
          boxShadow: AppShadow.card,
        ),
        child: Material(type: MaterialType.transparency, child: child),
      );
}

/// Round surface chip for a control sitting on the map (the back button).
class _MapChip extends StatelessWidget {
  const _MapChip({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surface,
          shape: BoxShape.circle,
          boxShadow: AppShadow.card,
        ),
        child: child,
      );
}
