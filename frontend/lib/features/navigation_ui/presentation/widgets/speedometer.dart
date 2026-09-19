import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';

class Speedometer extends StatelessWidget {
  final double speed;

  const Speedometer({super.key, this.speed = 0});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          speed.toStringAsFixed(1),
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 40,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
        Text('m/s', style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}
