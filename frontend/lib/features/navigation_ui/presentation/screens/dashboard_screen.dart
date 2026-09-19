import 'package:flutter/material.dart';

import '../../../../core/constants/dr_constants.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/geo_format.dart';
import '../../../../core/widgets/motion.dart';
import '../../../navigation_engine/domain/entities/navigation_state.dart';
import '../controllers/live_session_controller.dart';
import '../controllers/live_session_scope.dart';
import '../widgets/ai_inference_panel.dart';
import '../widgets/dashboard_header.dart';
import '../widgets/engine_status_card.dart';
import '../widgets/fusion_confidence_badge.dart';
import '../widgets/location_status_banner.dart';
import '../widgets/navic_weight_indicator.dart';
import '../widgets/navigation_map.dart';
import '../widgets/road_anomaly_ticker.dart';
import '../widgets/satellite_breakdown.dart';
import '../widgets/sensor_health_bar.dart';
import '../widgets/session_controls.dart';
import '../widgets/session_status_card.dart';
import '../widgets/telemetry_card.dart';
import '../widgets/thermal_compensation_card.dart';
import '../widgets/vehicle_profile_selector.dart';

/// Home screen. A pure view over the shared [LiveSessionController]: it owns
/// no sensors, timers or subscriptions.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Widget? _cached;

  @override
  Widget build(BuildContext context) {
    final session = LiveSessionScope.of(context);

    // While another screen (fullscreen navigation, diagnostics) covers this
    // one, re-use the last built tree instead of rebuilding it 10x a second.
    final isCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    final cached = _cached;
    if (!isCurrent && cached != null) return cached;

    return _cached = Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: ListView(
          // No top inset: the title sits directly under the status bar so
          // the screen does not open on a band of empty background.
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.xs,
            AppSpacing.md,
            AppSpacing.xl,
          ),
          children: [
            FadeSlideIn(child: DashboardHeader(session: session)),
            const SizedBox(height: AppSpacing.md),
            FadeSlideIn(
              delay: const Duration(milliseconds: 70),
              child: Column(
                children: [
                  LocationStatusBanner(location: session.location),
                  SessionStatusCard(session: session),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            FadeSlideIn(
              delay: const Duration(milliseconds: 140),
              child: _LivePositionSection(session: session),
            ),
            const SizedBox(height: AppSpacing.md),
            FadeSlideIn(
              delay: const Duration(milliseconds: 210),
              child: _DiagnosticsSection(session: session),
            ),
            const SizedBox(height: AppSpacing.md),
            FadeSlideIn(
              delay: const Duration(milliseconds: 280),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionHeader(
                    title: 'Vehicle profile',
                    subtitle: 'Tunes lean and bump handling for the filter',
                  ),
                  VehicleProfileSelector(
                    selected: session.vehicleProfile,
                    onChanged: session.setVehicleProfile,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            FadeSlideIn(
              delay: const Duration(milliseconds: 350),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionHeader(
                    title: 'Navigation core',
                    subtitle:
                        'The filter takes over once it knows how the phone sits '
                        'in the vehicle',
                  ),
                  EngineStatusCard(
                    snapshot: session.navSnapshot,
                    isLeading: session.isEngineLeading,
                    blocker: session.engineHandoverBlocker,
                    isRecording: session.isRecording,
                    recordedDuration: session.recordedDuration,
                    recordedLines: session.recordedLines,
                    recordingError: session.recordingError,
                    onStartRecording: () async {
                      final path = await session.startRecording();
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).hideCurrentSnackBar();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(path == null
                              ? 'Could not start recording — storage unavailable'
                              : 'Recording this drive. The screen stays on.'),
                          backgroundColor:
                              path == null ? AppColors.error : AppColors.cyan,
                          duration: const Duration(seconds: 3),
                        ),
                      );
                    },
                    onStopRecording: () async {
                      final file = await session.stopRecording();
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).hideCurrentSnackBar();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(file == null
                              ? 'Recording stopped'
                              : 'Saved ${file.name} '
                                  '(${file.sizeMb.toStringAsFixed(1)} MB)'),
                          backgroundColor: AppColors.healthy,
                          duration: const Duration(seconds: 3),
                        ),
                      );
                    },
                    onMarkEvent: () {
                      session.markEvent('driver marker');
                      ScaffoldMessenger.of(context).hideCurrentSnackBar();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Marked this moment in the log'),
                          backgroundColor: AppColors.cyan,
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const SectionHeader(
                    title: 'Scenarios',
                    subtitle: 'Simulate GNSS loss to see dead reckoning take over',
                  ),
                  SessionControls(
                    onTunnelTest: session.startTunnelTest,
                    onUrbanCanyon: session.startUrbanCanyon,
                    onResetGps: session.resetSimulation,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            FadeSlideIn(
              delay: const Duration(milliseconds: 420),
              child: PrimaryButton(
                label: 'Start fullscreen navigation',
                icon: Icons.navigation_rounded,
                onPressed: () => Navigator.pushNamed(context, '/session'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LivePositionSection extends StatelessWidget {
  const _LivePositionSection({required this.session});

  final LiveSessionController session;

  @override
  Widget build(BuildContext context) {
    final estimate = session.uncertainty;
    final margin = estimate?.marginMeters;
    final confidenceColor = FusionConfidenceBadge.colorFor(estimate?.confidence);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          title: 'Live position',
          subtitle: 'GNSS position with dead reckoning as fallback',
        ),
        NavigationMap(
          navigationState: session.navigationState,
          marginMeters: margin,
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TelemetryCard(
              label: 'Speed',
              value: session.speed.toStringAsFixed(1),
              unit: 'm/s',
              subtitle: '${(session.speed * 3.6).toStringAsFixed(1)} km/h',
              accentColor: AppColors.cyan,
            ),
            const SizedBox(width: AppSpacing.md),
            TelemetryCard(
              label: 'Heading',
              value: '${session.heading.round()}°',
              subtitle: 'Magnetometer',
              accentColor: AppColors.blue,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TelemetryCard(
              label: 'Position',
              value: formatLatitude(session.latitude),
              subtitle: '${formatLongitude(session.longitude)} · '
                  '${_positionSource(session)}',
              accentColor: session.inOutage
                  ? AppColors.error
                  : (session.hasLiveGnss ? AppColors.cyan : AppColors.warning),
            ),
            const SizedBox(width: AppSpacing.md),
            TelemetryCard(
              label: 'Accuracy',
              value: margin == null ? '—' : '±${margin.round()}',
              unit: margin == null ? null : 'm',
              subtitle: _accuracySubtitle(session),
              accentColor: confidenceColor,
            ),
          ],
        ),
      ],
    );
  }

  static String _positionSource(LiveSessionController s) {
    if (s.inOutage) return 'dead reckoning';
    if (s.hasLiveGnss) return 'GNSS fix';
    return 'last known';
  }

  static String _accuracySubtitle(LiveSessionController s) {
    if (s.inOutage) return 'Modelled drift margin';
    if (s.hasLiveGnss) return 'GNSS accuracy';
    return 'Waiting for a fix';
  }
}

class _DiagnosticsSection extends StatelessWidget {
  const _DiagnosticsSection({required this.session});

  final LiveSessionController session;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          title: 'Diagnostics',
          subtitle: 'Satellite and NavIC panels show demo values',
        ),
        SensorHealthBar(sensorHealth: session.sensorHealth),
        SatelliteBreakdown(satelliteBreakdown: _demoSatellites(session)),
        NavicWeightIndicator(navicWeight: _demoNavicWeight(session)),
        AiInferencePanel(
          inferenceStats: InferenceStatsModel(
            latencyMs:
                session.hasModelInference ? session.inferenceLatencyMs : null,
            modelVersion: session.isModelLoaded
                ? AppConstants.defaultModelVersion
                : 'Model not loaded',
            confidence:
                session.hasModelInference ? session.inferenceConfidence : null,
            estimatedSpeed:
                session.hasModelInference ? session.inferenceSpeed : null,
          ),
        ),
        ThermalCompensationCard(
          thermalState: ThermalStateModel(
            temperature: session.temperature,
            biasCorrection: session.thermalBias,
          ),
          vibrationLevel: session.vibrationLevel,
          vibrationRms: session.vibrationRms,
        ),
        RoadAnomalyTicker(anomalyEvents: session.anomalies),
      ],
    );
  }

  // Demo values: Android's GnssStatus API is not wired in yet, so these panels
  // illustrate the intended display. They are labelled as demo in the header.
  static SatelliteBreakdownModel _demoSatellites(LiveSessionController s) {
    if (!s.hasLiveGnss) {
      return const SatelliteBreakdownModel(
        navIC: SatelliteInfoModel(count: 4, signalStrength: 38.5),
        gps: SatelliteInfoModel(count: 0, signalStrength: 0.0),
        galileo: SatelliteInfoModel(count: 0, signalStrength: 0.0),
        glonass: SatelliteInfoModel(count: 0, signalStrength: 0.0),
      );
    }
    if (s.isSimulatingCanyon) {
      return const SatelliteBreakdownModel(
        navIC: SatelliteInfoModel(count: 4, signalStrength: 28.0),
        gps: SatelliteInfoModel(count: 2, signalStrength: 18.5),
        galileo: SatelliteInfoModel(count: 0, signalStrength: 0.0),
        glonass: SatelliteInfoModel(count: 0, signalStrength: 0.0),
      );
    }
    return const SatelliteBreakdownModel(
      navIC: SatelliteInfoModel(count: 7, signalStrength: 44.0),
      gps: SatelliteInfoModel(count: 9, signalStrength: 41.5),
      galileo: SatelliteInfoModel(count: 4, signalStrength: 32.0),
      glonass: SatelliteInfoModel(count: 5, signalStrength: 35.0),
    );
  }

  static double _demoNavicWeight(LiveSessionController s) {
    if (!s.hasLiveGnss) return 0.55;
    return s.isSimulatingCanyon ? 0.35 : 0.65;
  }
}
