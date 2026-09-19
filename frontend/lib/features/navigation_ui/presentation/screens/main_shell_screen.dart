import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
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
        child: IndexedStack(
          index: _currentIndex,
          children: [
            HomeTab(onNavigateToTab: _onTabSelected),
            const MapTab(),
            const SensorsTab(),
            const ProfileTab(),
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
          color: isSelected
              ? activeColor.withOpacity(0.12)
              : Colors.transparent,
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
