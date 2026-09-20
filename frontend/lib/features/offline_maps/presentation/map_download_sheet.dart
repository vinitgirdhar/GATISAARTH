import 'package:flutter/material.dart';

import '../../../core/platform/maps/map_download_service.dart';
import '../../../core/platform/maps/offline_catalog.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/motion.dart';
import '../domain/map_download_prompt.dart';
import 'region_card.dart' show megabytes;

/// Asks, once, whether to save the maps for where the person is.
///
/// Shows nothing else and starts nothing until a button is pressed. Closing it
/// any other way counts as "Not now", so it does not come back on the next
/// launch.
Future<void> showMapDownloadSheet(
  BuildContext context, {
  required MapOffer offer,
  required MapDownloadPrompter prompter,
  required MapDownloadService downloads,
}) async {
  var answered = false;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => MapDownloadSheet(
      offer: offer,
      prompter: prompter,
      downloads: downloads,
      onAnswered: () => answered = true,
    ),
  );
  if (!answered) await prompter.notNow(offer.region);
}

class MapDownloadSheet extends StatefulWidget {
  const MapDownloadSheet({
    super.key,
    required this.offer,
    required this.prompter,
    required this.downloads,
    required this.onAnswered,
  });

  final MapOffer offer;
  final MapDownloadPrompter prompter;
  final MapDownloadService downloads;
  final VoidCallback onAnswered;

  @override
  State<MapDownloadSheet> createState() => _MapDownloadSheetState();
}

class _MapDownloadSheetState extends State<MapDownloadSheet> {
  late final Set<String> _chosen = {for (final p in widget.offer.packs) p.id};

  List<OfflinePack> get _picked =>
      [for (final p in widget.offer.packs) if (_chosen.contains(p.id)) p];

  int get _bytes => _picked.fold(0, (sum, p) => sum + p.approxBytes);

  Future<void> _download() async {
    widget.onAnswered();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    if (!await widget.downloads.checkOnline()) {
      messenger.showSnackBar(const SnackBar(
        content: Text('No internet connection. Try again when you are online.'),
      ));
      if (mounted) navigator.pop();
      return;
    }
    widget.downloads.downloadAll(_picked);
    if (mounted) navigator.pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('Downloading ${_picked.length == 1 ? 'the map' : 'maps'}'
            '. Keep the app open.'),
        // A snackbar with an action never leaves by itself; this one is stale
        // as soon as the download ends.
        persist: false,
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: 'View',
          onPressed: () => navigator.pushNamed('/offline-maps'),
        ),
      ));
  }

  Future<void> _notNow() async {
    widget.onAnswered();
    await widget.prompter.notNow(widget.offer.region);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _never() async {
    widget.onAnswered();
    await widget.prompter.neverAsk(widget.offer.region);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final offer = widget.offer;
    final place =
        offer.headline.detail ? offer.headline.name : offer.region.name;

    final rows = <Widget>[
      Text(
        'Save maps for $place?',
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
          color: AppColors.textPrimary,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        'You are in ${offer.region.name}. Offline maps keep the roads and your '
        'position on screen in tunnels and dead zones, with no internet '
        'needed.',
        style: TextStyle(
          fontSize: 14,
          height: 1.45,
          color: AppColors.textSecondary,
        ),
      ),
      const SizedBox(height: 14),
      for (final pack in offer.packs)
        _PackChoice(
          pack: pack,
          checked: _chosen.contains(pack.id),
          onChanged: (on) => setState(() {
            on ? _chosen.add(pack.id) : _chosen.remove(pack.id);
          }),
        ),
      const SizedBox(height: 8),
      Text(
        'Uses mobile data if you are not on Wi-Fi. Keep the app open while '
        'it downloads; you can delete these maps any time in Profile > '
        'Offline Maps.',
        style: TextStyle(
          fontSize: 12,
          height: 1.4,
          color: AppColors.textMuted,
        ),
      ),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: _picked.isEmpty ? null : _download,
        icon: const Icon(Icons.download_rounded),
        label: Text(_picked.isEmpty
            ? 'Choose a map'
            : 'Download ${megabytes(_bytes)}'),
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.controlRadius),
        ),
      ),
      const SizedBox(height: 4),
      Row(
        children: [
          Expanded(
            child: TextButton(onPressed: _notNow, child: const Text('Not now')),
          ),
          Expanded(
            child: TextButton(
              onPressed: _never,
              child: const Text('Do not ask again'),
            ),
          ),
        ],
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: const [
          BoxShadow(color: Color(0x33000000), blurRadius: 24),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.textMuted.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Drops in from above, one row after another.
              for (var i = 0; i < rows.length; i++)
                FadeSlideIn(
                  delay: Duration(milliseconds: 45 * i),
                  offset: -0.08,
                  child: rows[i],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PackChoice extends StatelessWidget {
  const _PackChoice({
    required this.pack,
    required this.checked,
    required this.onChanged,
  });

  final OfflinePack pack;
  final bool checked;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final detail = pack.maxZoom >= 15
        ? 'Every street'
        : 'Roads, towns and coast across the state';
    return InkWell(
      borderRadius: AppRadius.controlRadius,
      onTap: () => onChanged(!checked),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Checkbox(
              value: checked,
              onChanged: (v) => onChanged(v ?? false),
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pack.name,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    detail,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              megabytes(pack.approxBytes),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
