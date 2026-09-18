import 'package:flutter/material.dart';

import '../../../../core/platform/hardware/vehicle_alignment_engine.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/motion.dart';

/// iOS-style segmented control: Car / Two-wheeler.
class VehicleProfileSelector extends StatelessWidget {
  const VehicleProfileSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final VehicleProfile selected;
  final ValueChanged<VehicleProfile> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceSubtle,
        borderRadius: AppRadius.controlRadius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _Option(
              label: 'Car',
              icon: Icons.directions_car_rounded,
              selected: selected == VehicleProfile.car,
              onTap: () => onChanged(VehicleProfile.car),
            ),
          ),
          Expanded(
            child: _Option(
              label: 'Two-wheeler',
              icon: Icons.two_wheeler_rounded,
              selected: selected == VehicleProfile.twoWheeler,
              onTap: () => onChanged(VehicleProfile.twoWheeler),
            ),
          ),
        ],
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: PressableScale(
        onTap: onTap,
        pressedScale: 0.96,
        child: AnimatedContainer(
          duration: AppMotion.of(context, AppMotion.fast),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: selected ? AppColors.surface : Colors.transparent,
            borderRadius: AppRadius.controlRadius,
            boxShadow: selected ? AppShadow.card : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? AppColors.cyan : AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected ? AppColors.cyan : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
