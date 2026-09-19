import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/motion.dart';

class SessionControls extends StatelessWidget {
  final VoidCallback? onTunnelTest;
  final VoidCallback? onUrbanCanyon;
  final VoidCallback? onResetGps;
  final VoidCallback? onReplay;

  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;
  final bool showBackground;
  final bool showDiagnostics;

  const SessionControls({
    Key? key,
    this.onTunnelTest,
    this.onUrbanCanyon,
    this.onResetGps,
    this.onReplay,
    this.margin,
    this.padding,
    this.showBackground = true,
    this.showDiagnostics = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final row = Row(
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
        if (showDiagnostics)
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
    );

    if (!showBackground) {
      return Padding(
        padding: padding ?? EdgeInsets.zero,
        child: row,
      );
    }

    return Container(
      margin: margin ?? const EdgeInsets.only(bottom: AppSpacing.md),
      padding: padding ?? const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.cardRadius,
        boxShadow: AppShadow.card,
      ),
      child: row,
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
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Semantics(
          button: true,
          label: label,
          excludeSemantics: true,
          child: PressableScale(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: accentColor.withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: accentColor, size: 20),
                  ),
                  const SizedBox(height: 6),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
