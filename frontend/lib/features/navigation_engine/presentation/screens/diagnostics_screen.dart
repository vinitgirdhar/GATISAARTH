import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/repositories/demo_navigation_repository.dart';
import '../../../navigation_ui/presentation/widgets/sensor_health_bar.dart';
import '../../../navigation_ui/presentation/widgets/satellite_breakdown.dart';
import '../../../navigation_ui/presentation/widgets/ai_inference_panel.dart';

class DiagnosticsScreen extends StatelessWidget {
  const DiagnosticsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final data = const DemoNavigationRepository().current;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Diagnostics'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            margin: const EdgeInsets.only(bottom: AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.12),
              borderRadius: AppRadius.cardRadius,
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline,
                    color: AppColors.warning, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Illustrative demo values — live satellite status is not '
                    'wired in yet, so this panel is not real sensor data.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          SensorHealthBar(sensorHealth: data.sensorHealth),
          SatelliteBreakdown(satelliteBreakdown: data.satelliteBreakdown),
          AiInferencePanel(inferenceStats: data.inferenceStats),
        ],
      ),
    );
  }
}
