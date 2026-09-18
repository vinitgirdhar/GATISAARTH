import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/motion.dart';

class SessionControls extends StatelessWidget {
  final VoidCallback? onTunnelTest;
  final VoidCallback? onUrbanCanyon;
  final VoidCallback? onResetGps;
  final VoidCallback? onReplay;

  const SessionControls({
    Key? key,
    this.onTunnelTest,
    this.onUrbanCanyon,
    this.onResetGps,
    this.onReplay,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.cardRadius,
        boxShadow: AppShadow.card,
      ),
      child: Row(
        children: [
          _buildControlButton(
            context,
            'Tunnel test',
            Icons.gps_off,
            AppColors.error,
            () {
              if (onTunnelTest != null) onTunnelTest!();
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                      'Simulating a GNSS blackout — pure INS dead reckoning'),
                  backgroundColor: AppColors.error,
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
          _buildControlButton(
            context,
            'Urban canyon',
            Icons.location_city,
            AppColors.warning,
            () {
              if (onUrbanCanyon != null) onUrbanCanyon!();
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content:
                      Text('Simulating an urban canyon — weak, multipath GNSS'),
                  backgroundColor: AppColors.warning,
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
          _buildControlButton(
            context,
            'Reset GNSS',
            Icons.gps_fixed,
            AppColors.healthy,
            () {
              if (onResetGps != null) onResetGps!();
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content:
                      Text('Simulation cleared — back to live GNSS status'),
                  backgroundColor: AppColors.healthy,
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
          _buildControlButton(
            context,
            'Diagnostics',
            Icons.analytics_outlined,
            AppColors.cyan,
            () {
              if (onReplay != null) onReplay!();
              Navigator.pushNamed(context, '/diagnostics');
            },
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton(
    BuildContext context,
    String label,
    IconData icon,
    Color accentColor,
    VoidCallback onTap,
  ) {
    return Expanded(
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: PressableScale(
          onTap: onTap,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  borderRadius: AppRadius.controlRadius,
                ),
                child: Icon(icon, color: accentColor),
              ),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
