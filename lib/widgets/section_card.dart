import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The rounded, bordered "card" background shared by most of the home
/// screen's content blocks (the station card, the empty-state card, the
/// volume card, the sleep-timer panel) — pulled out after noticing all
/// four built the exact same [BoxDecoration] by hand, differing only in
/// padding and, occasionally, corner radius.
class SectionCard extends StatelessWidget {
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final Widget child;

  const SectionCard({super.key, required this.child, required this.padding, this.borderRadius = 16});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border, width: 1.5),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: child,
    );
  }
}
