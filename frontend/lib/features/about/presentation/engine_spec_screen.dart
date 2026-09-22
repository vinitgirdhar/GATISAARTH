import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/dr_constants.dart';
import '../../../core/nav/nav_config.dart';
import '../../../core/platform/hardware/device_hardware.dart';
import '../../../core/platform/hardware/vehicle_alignment_engine.dart';
import '../../../core/platform/location/live_location_service.dart';
import '../../../core/platform/maps/offline_catalog.dart';
import '../../../core/platform/maps/offline_map_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/motion.dart';
import '../../navigation_engine/domain/entities/navigation_state.dart';
import '../../navigation_ui/presentation/controllers/live_session_controller.dart';
import '../../navigation_ui/presentation/controllers/live_session_scope.dart';

/// What the "GatiSaarth Navigation Engine" is, and what it is doing right now.
///
/// Everything here is either read from the running app (live state, the model's
/// own metadata file, the engine's configuration defaults, the maps actually
/// installed) or is a plain statement of how the code works. Accuracy claims
/// that only real drives can establish are not made: the limits section says so.
class EngineSpecScreen extends StatefulWidget {
  const EngineSpecScreen({super.key});

  @override
  State<EngineSpecScreen> createState() => _EngineSpecScreenState();
}

class _EngineSpecScreenState extends State<EngineSpecScreen> {
  late final Future<ModelFacts?> _model = ModelFacts.load();
  Future<DeviceInfo?>? _device;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _device ??= LiveSessionScope.of(context).deviceInfo();
  }

  @override
  Widget build(BuildContext context) {
    final session = LiveSessionScope.of(context);
    final maps = OfflineMapsScope.maybeOf(context);
    final config = NavConfig.defaults;

    final blocks = <Widget>[
      const _Hero(),
      _LiveCard(session: session),
      _Card(
        title: 'How it works',
        icon: Icons.account_tree_rounded,
        children: const [
          _Step(
            icon: Icons.sensors_rounded,
            title: 'Sense',
            text: 'Accelerometer, gyroscope, magnetometer, barometer (where '
                'fitted) and GNSS are merged onto one timeline, so a late or '
                'duplicate sample cannot distort the maths.',
          ),
          _Step(
            icon: Icons.screen_rotation_alt_rounded,
            title: 'Align',
            text: 'It learns how the phone sits in the vehicle from straight '
                'accelerate-and-brake events, so the phone can be mounted '
                'any way round.',
          ),
          _Step(
            icon: Icons.hub_rounded,
            title: 'Fuse',
            text: 'An error-state Kalman filter blends inertial motion with '
                'GNSS, and rejects fixes that could not be real (jumps, '
                'impossible acceleration, mock locations).',
          ),
          _Step(
            icon: Icons.rule_rounded,
            title: 'Constrain',
            text: 'Physical facts keep the estimate honest: a stopped vehicle '
                'has zero velocity, a car does not slide sideways, a barometer '
                'knows height.',
          ),
          _Step(
            icon: Icons.route_rounded,
            title: 'Carry on',
            text: 'When satellites are lost (tunnels, canyons, parking '
                'structures) it keeps estimating position from motion alone '
                'and reports how uncertain that estimate has become.',
          ),
          _Step(
            icon: Icons.swap_horiz_rounded,
            title: 'Hand over safely',
            text: 'The core only leads once it is healthy. Until then, and '
                'whenever it is not, the simpler pipeline drives the map, so '
                'the app is never worse than without it.',
          ),
        ],
      ),
      _Card(
        title: 'Specifications',
        icon: Icons.tune_rounded,
        children: [
          const _Row('Filter', '15-state error-state Kalman filter'),
          const _Row(
            'Estimated',
            'Position, velocity, attitude, accelerometer bias, gyroscope bias',
          ),
          _Row(
            'Prediction rate',
            'Up to ${config.sensors.maxFusionHz} Hz',
          ),
          _Row('Solution rate', '${config.power.uiHz} Hz to the screen'),
          const _Row(
            'Sensor sampling',
            'Accelerometer ≈ 50 Hz · gyroscope, magnetometer ≈ 15 Hz · '
                'barometer ≈ 5 Hz · GNSS 1 Hz',
          ),
          _Row(
            'GNSS "live"',
            'A real fix newer than ${session.location.staleAfter.inSeconds} s; '
                'a cached position never counts',
          ),
          const _Row(
            'Updates',
            'GNSS position and velocity, zero-velocity, zero angular rate, '
                'non-holonomic, barometric height, magnetometer heading',
          ),
          _Row(
            'Vehicle profiles',
            'Car: lateral slip limited to ${config.ekf.nhcSigmaCar} m/s. '
                'Two-wheeler: ${config.ekf.nhcSigmaTwoWheeler} m/s, for lean '
                'and swerve',
          ),
          _Row(
            'Mount alignment',
            'Needs ${config.alignment.minEvents} straight accelerate or brake '
                'events of at least '
                '${config.alignment.minLongitudinalAccel} m/s² (about 40 s of '
                'driving)',
          ),
          const _Row(
            'Uncertainty',
            'Read from the filter covariance and shown as ± metres; never '
                'a made-up number',
          ),
        ],
      ),
      FutureBuilder<ModelFacts?>(
        future: _model,
        builder: (context, snapshot) => _ModelCard(facts: snapshot.data),
      ),
      _MapsCard(maps: maps),
      _Card(
        title: 'Privacy and data',
        icon: Icons.shield_rounded,
        children: const [
          _Bullet(
            'Dead reckoning and the motion model run entirely on this phone. '
            'There is no account, no advertising and no analytics library.',
          ),
          _Bullet(
            'Nothing you record leaves the phone unless you share it. Drive '
            'recordings stay in the app\'s private storage; sharing sends '
            'a copy through Android\'s share sheet, after asking.',
          ),
          _Bullet(
            'An optional developer telemetry link only starts if a backend '
            'answers on the local network. On a normal phone none does.',
          ),
          _Bullet(
            'Outside the offline regions, map tiles may be fetched from '
            'Stadia Maps while you are online. That server sees which tiles '
            'you look at (roughly where you are) and your IP address, like '
            'any web request.',
          ),
        ],
      ),
      _Card(
        title: 'Known limits',
        icon: Icons.info_outline_rounded,
        children: const [
          _Bullet(
            'Accuracy figures in the outage benchmark come from a simulated '
            'drive. Real accuracy is only known after recorded drives are '
            'scored; the app does not claim it before that.',
          ),
          _Bullet(
            'Roads come from the offline maps installed on this phone: during '
            'a GNSS outage the position is held to the drawn road and matched '
            'to it. Where no map covers you this is off, and it works at road '
            'level, not lane level.',
          ),
          _Bullet(
            'Long outages drift: the longer GNSS is gone, the wider the '
            'uncertainty circle grows.',
          ),
          _Bullet(
            'The satellite breakdown on the Sensors tab is demonstration '
            'data, and is labelled as such.',
          ),
        ],
      ),
      FutureBuilder<DeviceInfo?>(
        future: _device,
        builder: (context, snapshot) =>
            _DeviceCard(session: session, info: snapshot.data),
      ),
      const _Links(),
    ];

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('Navigation engine')),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.xxl,
        ),
        itemCount: blocks.length,
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
        itemBuilder: (context, i) {
          final block = blocks[i];
          // Only animate initial fold blocks on page entrance.
          // Scrolled items are rendered immediately to prevent invisible content.
          if (i >= 3) return block;
          return FadeSlideIn(
            delay: Duration(milliseconds: 60 * i),
            offset: -0.05,
            child: block,
          );
        },
      ),
    );
  }
}

// ------------------------------------------------------------------- model

/// What the shipped model's own metadata file says about it.
@visibleForTesting
class ModelFacts {
  const ModelFacts({
    required this.version,
    required this.windowSamples,
    required this.rateHz,
    required this.features,
    required this.quantization,
    required this.sizeBytes,
    required this.speedMaeMps,
    required this.parity,
  });

  final String version;
  final int windowSamples;
  final double rateHz;
  final int features;
  final String quantization;
  final int? sizeBytes;
  final double? speedMaeMps;
  final String? parity;

  static Future<ModelFacts?> load({AssetBundle? bundle}) async {
    final assets = bundle ?? rootBundle;
    try {
      final json = jsonDecode(
        await assets.loadString('assets/models/model_metadata.json'),
      ) as Map<String, dynamic>;
      int? size;
      try {
        size = (await assets.load('assets/models/speed_estimator.tflite'))
            .lengthInBytes;
      } catch (_) {}
      return ModelFacts(
        version: '${json['model_version']}',
        windowSamples: (json['window_size_samples'] as num).toInt(),
        rateHz: (json['sampling_rate_hz'] as num).toDouble(),
        features: (json['input_features'] as num).toInt(),
        quantization: '${json['quantization']}'.toLowerCase(),
        sizeBytes: size,
        speedMaeMps: (json['speed_mae_m_s'] as num?)?.toDouble(),
        parity: json['parity_status'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}

class _ModelCard extends StatelessWidget {
  const _ModelCard({required this.facts});

  final ModelFacts? facts;

  @override
  Widget build(BuildContext context) {
    final f = facts;
    return _Card(
      title: 'Motion model (edge AI)',
      icon: Icons.memory_rounded,
      children: [
        _Row('Model', f == null ? 'SpeedEstimatorNet' : 'SpeedEstimatorNet ${f.version}'),
        const _Row('Type', '1-D convolutions with a bidirectional GRU'),
        if (f != null) ...[
          _Row(
            'Input',
            '${f.windowSamples} samples at ${f.rateHz.toStringAsFixed(0)} Hz '
                '(${(f.windowSamples / f.rateHz).toStringAsFixed(0)} s) × '
                '${f.features} features',
          ),
          _Row(
            'Format',
            'TensorFlow Lite, ${f.quantization}, built-in ops only'
                '${f.sizeBytes == null ? '' : ', ${(f.sizeBytes! / 1000).round()} KB'}',
          ),
          if (f.speedMaeMps != null)
            _Row(
              'Validation',
              'Speed error ${f.speedMaeMps} m/s on its offline, synthetic '
                  'validation set. Not a field accuracy figure.',
            ),
          if (f.parity != null) _Row('Conversion check', f.parity!),
        ],
        const _Row(
          'Role',
          'Advisory. It may stop the position marker when the phone is '
              'still; it never sets speed or position.',
        ),
      ],
    );
  }
}

// -------------------------------------------------------------------- maps

class _MapsCard extends StatelessWidget {
  const _MapsCard({required this.maps});

  final OfflineMapService? maps;

  @override
  Widget build(BuildContext context) {
    final m = maps;
    return _Card(
      title: 'Maps',
      icon: Icons.map_rounded,
      children: [
        const _Row(
          'Basemap',
          'OpenStreetMap data drawn on this phone from vector tiles '
              '(Protomaps, ${OfflineCatalog.dataBuild} build)',
        ),
        for (final region in OfflineCatalog.regions)
          _Row(
            region.name,
            m == null || m.isLoading
                ? 'Checking…'
                : m.installedCount(region) == region.packs.length
                    ? 'Ready offline'
                    : m.installedCount(region) > 0
                        ? '${m.installedCount(region)} of ${region.packs.length} files ready'
                        : 'Not in this build',
          ),
        const _Row(
          'Elsewhere',
          'Cached tiles, and Stadia Maps tiles while online',
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => Navigator.pushNamed(context, '/offline-maps'),
            icon: const Icon(Icons.download_done_rounded, size: 18),
            label: const Text('Manage offline maps'),
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------- live + device

class _LiveCard extends StatelessWidget {
  const _LiveCard({required this.session});

  final LiveSessionController session;

  static String _gnss(LocationStatus s) => switch (s) {
        LocationStatus.live => 'Live fix',
        LocationStatus.searching => 'Searching for satellites',
        LocationStatus.stale => 'Signal lost',
        LocationStatus.serviceOff => 'Location is off',
        LocationStatus.permissionDenied => 'Permission needed',
        LocationStatus.permissionBlocked => 'Permission blocked',
        LocationStatus.initializing => 'Starting',
      };

  @override
  Widget build(BuildContext context) {
    final leading = session.isEngineLeading;
    return _Card(
      title: 'Right now',
      icon: Icons.bolt_rounded,
      children: [
        _Row('Position', session.fusionMode.label),
        _Row('Satellites', _gnss(session.gnssStatus)),
        _Row('Solution from', leading ? 'Navigation core' : 'Fallback pipeline'),
        if (!leading)
          _Row('Core waiting for', session.engineHandoverBlocker ?? '—'),
        _Row('Sensors', session.isSensorLive ? 'Streaming' : 'Idle'),
        _Row(
          'Motion model',
          session.isSpeedEstimatorReady
              ? 'Ready'
              : (session.isModelLoaded ? 'Starting' : 'Not loaded'),
        ),
        _Row(
          'Vehicle profile',
          switch (session.vehicleProfile) {
            VehicleProfile.car => 'Car',
            VehicleProfile.twoWheeler => 'Two-wheeler',
            VehicleProfile.pedestrian => 'Pedestrian / last-mile',
          },
        ),
      ],
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.session, required this.info});

  final LiveSessionController session;
  final DeviceInfo? info;

  @override
  Widget build(BuildContext context) {
    final health = session.sensorHealth;
    String yes(bool ok) => ok ? 'Present' : 'Not available';
    return _Card(
      title: 'This phone',
      icon: Icons.smartphone_rounded,
      children: [
        _Row('Device', info?.model ?? '—'),
        _Row('System', info?.os ?? Platform.operatingSystem),
        _Row('Accelerometer', yes(health.accelerometer)),
        _Row('Gyroscope', yes(health.gyroscope)),
        _Row('Magnetometer', yes(health.magnetometer)),
        _Row('Barometer', yes(health.barometer)),
      ],
    );
  }
}

// ------------------------------------------------------------------ chrome

class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: AppRadius.cardRadius,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0A84FF), Color(0xFF5856D6)],
        ),
        boxShadow: AppShadow.floating,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.explore_rounded, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 14),
          const Text(
            'GatiSaarth Navigation Engine',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Offline-first navigation that keeps going when GNSS stops.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 14,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          const Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _HeroChip('v${AppConstants.appVersion} (build ${AppConstants.appBuild})'),
              _HeroChip('On-device'),
              _HeroChip('Offline maps'),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.icon, required this.children});

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : AppColors.lightSurfaceBorder,
        ),
        boxShadow: AppShadow.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: AppColors.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.icon, required this.title, required this.text});

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  text,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: AppColors.textSecondary,
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

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Links extends StatelessWidget {
  const _Links();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _LinkButton(
          icon: Icons.bug_report_rounded,
          label: 'Diagnostics console',
          onTap: () => Navigator.pushNamed(context, '/diagnostics'),
        ),
        const SizedBox(height: 8),
        _LinkButton(
          icon: Icons.speed_rounded,
          label: 'Outage benchmark',
          onTap: () => Navigator.pushNamed(context, '/benchmark'),
        ),
        const SizedBox(height: 8),
        _LinkButton(
          icon: Icons.description_outlined,
          label: 'Open-source licences',
          onTap: () => showLicensePage(
            context: context,
            applicationName: AppConstants.appTitle,
            applicationVersion:
                '${AppConstants.appVersion} (${AppConstants.appBuild})',
          ),
        ),
      ],
    );
  }
}

class _LinkButton extends StatelessWidget {
  const _LinkButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      borderRadius: AppRadius.controlRadius,
      child: InkWell(
        borderRadius: AppRadius.controlRadius,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: AppRadius.controlRadius,
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : AppColors.lightSurfaceBorder,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: AppColors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
