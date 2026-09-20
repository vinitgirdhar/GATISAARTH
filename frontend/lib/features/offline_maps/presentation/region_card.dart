import 'package:flutter/material.dart';

import '../../../core/platform/maps/map_download_service.dart';
import '../../../core/platform/maps/offline_catalog.dart';
import '../../../core/platform/maps/offline_map_service.dart';
import '../../../core/platform/maps/pack_reader.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/motion.dart';

/// "37 MB", "4.0 MB".
String megabytes(int bytes) {
  final mb = bytes / 1e6;
  return mb >= 10 ? '${mb.round()} MB' : '${mb.toStringAsFixed(1)} MB';
}

/// Downloads above this ask first: they are big enough to matter on mobile
/// data.
const int kConfirmDownloadBytes = 30 * 1000 * 1000;

/// Card surface shared by the Offline Maps blocks.
class MapsSurface extends StatelessWidget {
  const MapsSurface({super.key, required this.child, this.highlighted = false});

  final Widget child;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AppMotion.of(context, AppMotion.medium),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(
          color: highlighted
              ? AppColors.primary.withValues(alpha: 0.6)
              : AppColors.surfaceBorder,
          width: highlighted ? 1.5 : 1,
        ),
        boxShadow: AppShadow.card,
      ),
      child: child,
    );
  }
}

/// Starts downloading [packs] after the checks a person would want: is there a
/// connection, and - for a big download - do they mean it.
Future<void> requestDownload(
  BuildContext context,
  MapDownloadService downloads,
  List<OfflinePack> packs, {
  String? name,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final total = packs.fold<int>(0, (s, p) => s + p.approxBytes);

  if (total >= kConfirmDownloadBytes) {
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Download ${name ?? 'these maps'}?'),
        content: Text(
          '${megabytes(total)} will be saved on this phone. It uses mobile '
          'data if you are not on Wi-Fi. Keep the app open while it '
          'downloads.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Download ${megabytes(total)}'),
          ),
        ],
      ),
    );
    if (go != true) return;
  }

  if (!await downloads.checkOnline()) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: Text(
          'No internet connection. Connect to Wi-Fi or mobile data, then '
          'try again.',
        ),
      ));
    return;
  }
  downloads.downloadAll(packs);
}

/// Asks before removing a map, and removes it.
Future<void> confirmDelete(
  BuildContext context,
  MapDownloadService downloads,
  OfflinePack pack,
  int bytes,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final go = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Delete ${pack.name}?'),
      content: Text(
        'This frees ${megabytes(bytes)}. Navigation there will need a '
        'connection until you download it again.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.error),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (go != true) return;
  final removed = await downloads.delete(pack);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(removed
          ? '${pack.name} deleted. ${megabytes(bytes)} freed.'
          : 'Could not delete ${pack.name}.'),
    ));
}

/// One region: its status, its maps with a download or delete control each, and
/// the actions that apply to the whole region.
class RegionCard extends StatelessWidget {
  const RegionCard({
    super.key,
    required this.region,
    required this.service,
    required this.downloads,
    required this.selected,
    required this.onShow,
  });

  final OfflineRegion region;
  final OfflineMapService? service;
  final MapDownloadService? downloads;
  final bool selected;
  final VoidCallback onShow;

  @override
  Widget build(BuildContext context) {
    final s = service;
    final installed = s?.installedCount(region) ?? 0;
    final total = region.packs.length;
    final loading = s == null ? false : s.isLoading;
    final working = downloads != null &&
        region.packs.any((p) {
          final t = downloads!.taskFor(p.id);
          return t != null && t.phase != PackPhase.failed;
        });

    final (label, color) = loading
        ? ('Checking', AppColors.textSecondary)
        : working
            ? ('Downloading', AppColors.primary)
            : installed == total
                ? ('Ready offline', AppColors.success)
                : installed > 0
                    ? ('Partly on this phone', AppColors.warning)
                    : ('Not on this phone', AppColors.textSecondary);

    final missing = [
      for (final p in region.packs)
        if (!(s?.isInstalled(p.id) ?? false)) p,
    ];
    final missingBytes = missing.fold<int>(0, (sum, p) => sum + p.approxBytes);

    return MapsSurface(
      highlighted: selected,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  region.name,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              StatusPill(label: label, color: color),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            region.summary,
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          for (final pack in region.packs)
            PackRow(pack: pack, service: s, downloads: downloads),
          const SizedBox(height: 6),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: onShow,
                icon: const Icon(Icons.travel_explore_rounded, size: 18),
                label: const Text('Show on map'),
              ),
              if (downloads != null && !loading && missing.isNotEmpty)
                FilledButton.tonalIcon(
                  onPressed: working
                      ? null
                      : () => requestDownload(
                            context,
                            downloads!,
                            missing,
                            name: region.name,
                          ),
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: Text(
                    missing.length == 1
                        ? 'Download ${megabytes(missingBytes)}'
                        : 'Download all ${megabytes(missingBytes)}',
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One map: what it is, where it is stored, and the control that fits.
class PackRow extends StatelessWidget {
  const PackRow({
    super.key,
    required this.pack,
    required this.service,
    required this.downloads,
  });

  final OfflinePack pack;
  final OfflineMapService? service;
  final MapDownloadService? downloads;

  @override
  Widget build(BuildContext context) {
    final s = service;
    final installed = s?.installedPack(pack.id);
    final problem = s?.problemWith(pack.id);
    final task = downloads?.taskFor(pack.id);
    final bytes = installed?.bytes ?? pack.approxBytes;
    final busy = task != null && task.phase != PackPhase.failed;

    final detail = pack.maxZoom >= 15
        ? 'Every street · zoom ${pack.maxZoom}'
        : 'Roads, towns and coast · zoom ${pack.maxZoom}';
    final where = switch (installed?.origin) {
      PackOrigin.bundled => 'Included with the app',
      PackOrigin.downloaded => 'Downloaded',
      PackOrigin.sideloaded => 'Copied to this phone',
      null => null,
    };

    final IconData icon;
    final Color iconColor;
    if (problem != null || task?.phase == PackPhase.failed) {
      icon = Icons.error_outline_rounded;
      iconColor = AppColors.error;
    } else if (installed != null) {
      icon = Icons.check_circle_rounded;
      iconColor = AppColors.success;
    } else if (busy) {
      icon = Icons.downloading_rounded;
      iconColor = AppColors.primary;
    } else {
      icon = Icons.radio_button_unchecked_rounded;
      iconColor = AppColors.textMuted;
    }

    final String subtitle;
    Color subtitleColor = AppColors.textSecondary;
    if (problem != null) {
      subtitle = 'Could not be opened';
      subtitleColor = AppColors.error;
    } else if (task?.phase == PackPhase.failed) {
      subtitle = task!.error ?? 'The download did not finish.';
      subtitleColor = AppColors.error;
    } else if (task?.phase == PackPhase.downloading) {
      subtitle = 'Downloading · ${(task!.fraction * 100).round()}%';
    } else if (task?.phase == PackPhase.queued) {
      subtitle = 'Waiting for the map before it';
    } else if (installed != null) {
      subtitle = '$detail · $where';
    } else {
      subtitle = detail;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(icon, size: 20, color: iconColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pack.name,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 12, color: subtitleColor),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _trailing(context, installed, task, bytes),
            ],
          ),
          if (task?.phase == PackPhase.downloading)
            Padding(
              padding: const EdgeInsets.fromLTRB(30, 8, 0, 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(end: task!.fraction),
                  duration: AppMotion.of(context, AppMotion.fast),
                  builder: (context, value, _) => LinearProgressIndicator(
                    value: value,
                    minHeight: 5,
                    backgroundColor: AppColors.surfaceSubtle,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _trailing(
    BuildContext context,
    InstalledPack? installed,
    PackTask? task,
    int bytes,
  ) {
    final d = downloads;
    final size = Text(
      megabytes(bytes),
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppColors.textSecondary,
      ),
    );

    if (task?.phase == PackPhase.downloading ||
        task?.phase == PackPhase.queued) {
      return IconButton(
        tooltip: 'Cancel',
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.close_rounded, size: 20),
        onPressed: d == null ? null : () => d.cancel(pack.id),
      );
    }
    if (task?.phase == PackPhase.failed) {
      return TextButton(
        onPressed: d == null
            ? null
            : () => requestDownload(context, d, [pack], name: pack.name),
        child: const Text('Retry'),
      );
    }
    if (installed != null) {
      if (installed.origin == PackOrigin.bundled || d == null) return size;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          size,
          IconButton(
            tooltip: 'Delete ${pack.name}',
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.delete_outline_rounded,
                size: 20, color: AppColors.textSecondary),
            onPressed: () => confirmDelete(context, d, pack, bytes),
          ),
        ],
      );
    }
    if (d == null) return size;
    return TextButton.icon(
      onPressed: () => requestDownload(context, d, [pack], name: pack.name),
      icon: const Icon(Icons.download_rounded, size: 18),
      label: Text(megabytes(pack.approxBytes)),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
