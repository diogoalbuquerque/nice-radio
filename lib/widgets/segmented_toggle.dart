// The "Favoritas / Todas" two-tab switch. Used identically on the home
// screen and the station list screen — written once here instead of
// twice so the two never visually drift apart.
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class SegmentedToggle extends StatelessWidget {
  final String leftLabel;
  final String rightLabel;
  final bool isLeftSelected;
  final VoidCallback onSelectLeft;
  final VoidCallback onSelectRight;

  const SegmentedToggle({
    super.key,
    required this.leftLabel,
    required this.rightLabel,
    required this.isLeftSelected,
    required this.onSelectLeft,
    required this.onSelectRight,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.chipBackground,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(child: _tab(leftLabel, isLeftSelected, onSelectLeft)),
          Expanded(child: _tab(rightLabel, !isLeftSelected, onSelectRight)),
        ],
      ),
    );
  }

  Widget _tab(String label, bool selected, VoidCallback onTap) {
    return Material(
      color: selected ? AppColors.primary : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          // WHY FittedBox: at larger system font sizes (this app's
          // audience often has one set — see the Atkinson Hyperlegible
          // choice in this file's own doc comment) "Favoritas" no longer
          // fit next to "Todas" at a fixed font size, and the two labels
          // started overlapping each other's rounded pill. FittedBox
          // shrinks the text just enough to keep it on one line and
          // inside its own half, instead of letting it overflow into the
          // neighboring tab.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: selected ? Colors.white : AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
