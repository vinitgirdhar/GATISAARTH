import 'package:flutter/material.dart';

import '../../../../core/nav/map/tunnel_lookahead.dart';
import '../../../../core/theme/app_theme.dart';
import 'status_strip.dart';

/// Warns before a tunnel from the offline map, then counts down the tunnel
/// still to drive. Says whether the AI speed aid has been validated against
/// GNSS on this drive, because inside it that is what holds the speed.
class TunnelAheadCard extends StatelessWidget {
  const TunnelAheadCard({
    super.key,
    required this.tunnel,
    required this.speedAidValidated,
  });

  final TunnelAhead tunnel;
  final bool speedAidValidated;

  @override
  Widget build(BuildContext context) {
    final t = tunnel;
    final name = t.name == null ? '' : '${t.name} · ';
    final headline = t.inside
        ? 'In tunnel · ${formatDistance(t.remainingM)} to the exit'
        : 'Tunnel ahead · ${formatDistance(t.distanceM)}';
    final aid = speedAidValidated
        ? 'speed aid validated on this drive'
        : 'speed aid not validated yet';
    final detail = t.inside
        ? '$name${formatDistance(t.lengthM)} long · dead reckoning · $aid'
        : '$name${formatDistance(t.lengthM)} long · '
            'dead reckoning takes over inside · $aid';
    return StatusStrip(
      icon: Icons.subway_outlined,
      color: t.inside ? AppColors.deadReckoning : AppColors.warning,
      headline: headline,
      detail: detail,
    );
  }
}
