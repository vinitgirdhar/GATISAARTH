import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Reusable, standardized card matching the UI/UX board design system.
///
/// Features:
/// - Dark slate surface `Color(0xFF1E293B)` in dark mode, pure white in light mode.
/// - 1px subtle border (`0xFF334155` dark / `0xFFE2E8F0` light).
/// - 16px continuous squircle corner radius.
/// - Standardized padding (default 20px) preventing content from touching card edges.
/// - Optional header section with title, subtitle, and trailing badge/action.
class StandardCard extends StatelessWidget {
  const StandardCard({
    super.key,
    this.titleText,
    this.title,
    this.subtitleText,
    this.subtitle,
    this.trailing,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.margin = const EdgeInsets.only(bottom: AppSpacing.md),
    this.onTap,
  });

  final String? titleText;
  final Widget? title;
  final String? subtitleText;
  final Widget? subtitle;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark;

    final hasHeader =
        titleText != null || title != null || subtitleText != null || subtitle != null || trailing != null;

    final cardContent = Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasHeader) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (titleText != null)
                        Text(
                          titleText!,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                            color: isDark
                                ? const Color(0xFF94A3B8)
                                : const Color(0xFF64748B),
                            fontFamily: 'Inter',
                          ),
                        )
                      else if (title != null)
                        title!,
                      if (subtitleText != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitleText!,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                            color: isDark
                                ? const Color(0xFF64748B)
                                : const Color(0xFF94A3B8),
                            fontFamily: 'Inter',
                          ),
                        ),
                      ] else if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        subtitle!,
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 8),
                  trailing!,
                ],
              ],
            ),
            const SizedBox(height: 14),
          ],
          child,
        ],
      ),
    );

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.25 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: onTap != null
            ? InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(16),
                child: cardContent,
              )
            : cardContent,
      ),
    );
  }
}
