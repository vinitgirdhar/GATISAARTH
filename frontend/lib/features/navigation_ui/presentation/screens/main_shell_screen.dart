import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import '../../../../core/platform/maps/map_download_service.dart';
import '../../../../core/platform/maps/offline_map_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/fade_indexed_stack.dart';
import '../../../offline_maps/domain/map_download_prompt.dart';
import '../../../offline_maps/presentation/map_download_sheet.dart';
import '../controllers/live_session_controller.dart';
import '../controllers/live_session_scope.dart';
import '../widgets/sync_capsule.dart';
import 'tabs/home_tab.dart';
import 'tabs/map_tab.dart';
import 'tabs/sensors_tab.dart';
import 'tabs/profile_tab.dart';

class MainShellScreen extends StatefulWidget {
  const MainShellScreen({
    Key? key,
    this.initialTab = 0,
  }) : super(key: key);

  final int initialTab;

  @override
  State<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends State<MainShellScreen> {
  late int _currentIndex = widget.initialTab;

  LiveSessionController? _session;
  bool _offerDone = false;
  bool _offerRunning = false;
  DateTime _offerNotBefore = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Read without subscribing: this listener wants the first position, not a
    // rebuild of the whole shell ten times a second.
    final session =
        context.getInheritedWidgetOfExactType<LiveSessionScope>()?.notifier;
    if (session != null && session != _session) {
      _session?.removeListener(_maybeOfferMaps);
      _session = session..addListener(_maybeOfferMaps);
    }
  }

  @override
  void dispose() {
    _session?.removeListener(_maybeOfferMaps);
    super.dispose();
  }

  /// Once, after the first real position: if the person is somewhere the app has
  /// maps for and they are not on the phone, offer to download them.
  Future<void> _maybeOfferMaps() async {
    final session = _session;
    if (_offerDone || _offerRunning || session == null) return;
    if (!session.hasLiveGnss || session.uncertainty == null) return;
    if (DateTime.now().isBefore(_offerNotBefore)) return;

    final maps = OfflineMapsScope.maybeOf(context);
    final downloads = MapDownloadsScope.maybeOf(context);
    if (maps == null || downloads == null || !downloads.offerOnFirstFix) {
      _offerDone = true;
      return;
    }
    if (!maps.isLoaded || downloads.isBusy) return;

    _offerRunning = true;
    try {
      final offer = await MapDownloadPrompter(maps: maps)
          .offerAt(LatLng(session.latitude, session.longitude));
      if (offer == null) {
        _offerDone = true;
        return;
      }
      if (!await downloads.checkOnline()) {
        // No connection right now: ask again in a minute rather than not at all.
        _offerNotBefore = DateTime.now().add(const Duration(minutes: 1));
        return;
      }
      // Let the start-up settle, and never put a sheet over another screen.
      await Future<void>.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      if (ModalRoute.of(context)?.isCurrent != true) {
        _offerNotBefore = DateTime.now().add(const Duration(seconds: 20));
        return;
      }
      _offerDone = true;
      await showMapDownloadSheet(
        context,
        offer: offer,
        prompter: MapDownloadPrompter(maps: maps),
        downloads: downloads,
      );
    } finally {
      _offerRunning = false;
    }
  }

  void _onTabSelected(int index) {
    if (_currentIndex == index) return;
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            FadeIndexedStack(
              index: _currentIndex,
              children: [
                HomeTab(onNavigateToTab: _onTabSelected),
                const MapTab(),
                const SensorsTab(),
                const ProfileTab(),
              ],
            ),
            // Its own Builder, so the 10 Hz session updates rebuild only the
            // capsule and not the whole shell.
            Positioned(
              top: AppSpacing.sm,
              left: 0,
              right: 0,
              child: Center(
                child: Builder(
                  builder: (context) => SyncCapsule(
                    status: LiveSessionScope.of(context).syncStatus,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
          border: Border(
            top: BorderSide(
              color: isDark
                  ? Colors.white.withOpacity(0.08)
                  : AppColors.lightSurfaceBorder,
              width: 0.8,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.35 : 0.06),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _NavBarItem(
                  icon: Icons.home_rounded,
                  label: 'Home',
                  isSelected: _currentIndex == 0,
                  onTap: () => _onTabSelected(0),
                ),
                _NavBarItem(
                  icon: Icons.map_rounded,
                  label: 'Map',
                  isSelected: _currentIndex == 1,
                  onTap: () => _onTabSelected(1),
                ),
                _NavBarItem(
                  icon: Icons.sensors_rounded,
                  label: 'Sensors',
                  isSelected: _currentIndex == 2,
                  onTap: () => _onTabSelected(2),
                ),
                _NavBarItem(
                  icon: Icons.person_rounded,
                  label: 'Profile',
                  isSelected: _currentIndex == 3,
                  onTap: () => _onTabSelected(3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavBarItem extends StatelessWidget {
  const _NavBarItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final activeColor = AppColors.primary;
    final inactiveColor = AppColors.textSecondary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color:
              isSelected ? activeColor.withOpacity(0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 24,
              color: isSelected ? activeColor : inactiveColor,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected ? activeColor : inactiveColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
