import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';

class CustomCompass extends StatelessWidget {
  final double heading;

  const CustomCompass({super.key, this.heading = 0});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${heading.round()}°',
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 32,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
        Text('Heading', style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}
