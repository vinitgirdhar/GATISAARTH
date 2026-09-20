import 'package:flutter/material.dart';
import '../../../../../core/theme/app_theme.dart';
import '../../../../../core/utils/geo_format.dart';
import '../../controllers/live_session_controller.dart';
import '../../controllers/live_session_scope.dart';
import '../../widgets/fusion_confidence_badge.dart';
import '../../widgets/navigation_map.dart';
import '../../widgets/session_controls.dart';
import '../../widgets/telemetry_card.dart';

const double _sheetRadius = 22;

class MapTab extends StatelessWidget {
  const MapTab({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final session = LiveSessionScope.of(context);
    final estimate = session.uncertainty;
    final margin = estimate?.marginMeters;
    final isDark = AppColors.isDark;

    return Column(
      children: [
        // 1. Top Exact Location Card (replaces mock 300 m guidance)
        Container(
          margin: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark
                  ? Colors.white.withOpacity(0.08)
                  : AppColors.lightSurfaceBorder,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.3 : 0.06),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.my_location_rounded,
                  color: AppColors.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Exact Location',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: session.inOutage
                                  ? AppColors.error.withOpacity(0.15)
                                  : AppColors.success.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              session.inOutage ? 'DEAD RECKONING' : 'GNSS LOCKED',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: session.inOutage
                                    ? AppColors.error
                                    : AppColors.success,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${formatLatitude(session.latitude)}, ${formatLongitude(session.longitude)}${margin != null ? ' · ±${margin.round()} m' : ''}',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        fontFamily: 'RobotoMono',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // 2. Interactive Navigation Map. Fills all the space between the card
        // above and the sheet below, and runs [_sheetRadius] underneath the
        // sheet so its rounded top corners show map, not page background.
        Expanded(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                bottom: -_sheetRadius,
                child: NavigationMap(
                  navigationState: session.navigationState,
                  marginMeters: margin,
                  expand: true,
                  bottomInset: _sheetRadius + 12,
                ),
              ),

              // Floating Controls (below the OSM credit line, which the map
              // draws top-right and licensing requires to stay readable)
              Positioned(
                right: 16,
                top: 40,
                child: Column(
                  children: [
                    _FloatingMapButton(
                      icon: Icons.fullscreen_rounded,
                      onTap: () => Navigator.pushNamed(context, '/session'),
                    ),
                    const SizedBox(height: 8),
                    _FloatingMapButton(
                      icon: Icons.my_location_rounded,
                      onTap: () {},
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // 3. Bottom Telemetry & Simulation Controls
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(_sheetRadius)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.3 : 0.08),
                blurRadius: 14,
                offset: const Offset(0, -3),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Telemetry metrics row
              Row(
                children: [
                  TelemetryCard(
                    label: 'Speed',
                    value: (session.speed * 3.6).toStringAsFixed(0),
                    unit: 'km/h',
                    subtitle: '${session.speed.toStringAsFixed(1)} m/s',
                    accentColor: AppColors.primary,
                  ),
                  const SizedBox(width: 8),
                  TelemetryCard(
                    label: 'Heading',
                    value: '${session.heading.round()}°',
                    subtitle: 'Compass',
                    accentColor: AppColors.secondary,
                  ),
                  const SizedBox(width: 8),
                  TelemetryCard(
                    label: 'Accuracy',
                    value: margin == null ? '—' : '±${margin.round()}',
                    unit: margin == null ? null : 'm',
                    subtitle: session.inOutage ? 'Dead reckoning' : 'GNSS fix',
                    accentColor: FusionConfidenceBadge.colorFor(
                        estimate?.confidence),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Outage & Simulation Controls
              SessionControls(
                showBackground: false,
                showDiagnostics: false,
                margin: EdgeInsets.zero,
                padding: const EdgeInsets.only(top: 10),
                onTunnelTest: session.startTunnelTest,
                onUrbanCanyon: session.startUrbanCanyon,
                onResetGps: session.resetSimulation,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FloatingMapButton extends StatelessWidget {
  const _FloatingMapButton({
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark
                ? Colors.white.withOpacity(0.1)
                : AppColors.lightSurfaceBorder,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, size: 20, color: AppColors.textPrimary),
      ),
    );
  }
}
