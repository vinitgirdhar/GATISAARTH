import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/standard_card.dart';

/// Two live readings side by side: the phone's temperature (it shifts MEMS
/// biases, which is why the core re-checks its calibration when it moves) and
/// how rough the road currently is.
class PhoneConditionCard extends StatelessWidget {
  const PhoneConditionCard({
    super.key,
    required this.temperatureC,
    required this.vibrationLevel,
    required this.vibrationRms,
  });

  /// Null until the phone has reported a temperature.
  final double? temperatureC;
  final String vibrationLevel;
  final double vibrationRms;

  @override
  Widget build(BuildContext context) {
    final t = temperatureC;
    return StandardCard(
      child: Row(
        children: [
          Expanded(
            child: _Reading(
              label: 'Phone temperature',
              value: t == null ? '--' : '${t.toStringAsFixed(1)}°C',
            ),
          ),
          Container(
            width: 1,
            height: 38,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            color: AppColors.isDark
                ? const Color(0xFF334155).withValues(alpha: 0.6)
                : const Color(0xFFE2E8F0),
          ),
          Expanded(
            child: _Reading(
              label: 'Road vibration',
              value: '${_capitalised(vibrationLevel)} · '
                  '${vibrationRms.toStringAsFixed(2)} g',
            ),
          ),
        ],
      ),
    );
  }

  static String _capitalised(String s) =>
      s.isEmpty ? s : s[0] + s.substring(1).toLowerCase();
}

class _Reading extends StatelessWidget {
  const _Reading({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.isDark
                ? const Color(0xFF94A3B8)
                : const Color(0xFF64748B),
            letterSpacing: 0.2,
            fontFamily: 'Inter',
          ),
        ),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              fontFamily: 'Inter',
            ),
          ),
        ),
      ],
    );
  }
}
