import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// "Favoritar" and "Dormir" side by side, always sharing one height —
/// see the `IntrinsicHeight`/`stretch` doc below for why that needs more
/// than the default `Row`.
class ActionButtonsRow extends StatelessWidget {
  final bool isFavorite;
  final int sleepMinutes;
  final bool sleepPanelOpen;
  final bool hasStation;
  final VoidCallback? onToggleFavorite;
  final VoidCallback onToggleSleepPanel;

  const ActionButtonsRow({
    super.key,
    required this.isFavorite,
    required this.sleepMinutes,
    required this.sleepPanelOpen,
    required this.hasStation,
    required this.onToggleFavorite,
    required this.onToggleSleepPanel,
  });

  @override
  Widget build(BuildContext context) {
    // `IntrinsicHeight` + `stretch` (not the default `center`) so both
    // buttons share one height — whichever needs the most room (its label
    // wrapping to a second line at a larger system text size, for
    // instance) sets the height for the other, instead of each button
    // independently hugging its own content and ending up a visibly
    // different size from its neighbor.
    //
    // WHY `IntrinsicHeight` is required, not just `stretch` on its own:
    // this row lives inside a scrollable column, which gives it an
    // *unbounded* height constraint (that's what makes scrolling
    // possible at all). `CrossAxisAlignment.stretch` needs a concrete
    // number to stretch children *to* — with nothing bounding the
    // height, Flutter has no such number and throws at runtime (this
    // was tried without `IntrinsicHeight` first, and crashed the whole
    // screen to a blank page — caught by the same manual browser check
    // this file's other UI fixes go through, not by `flutter analyze`,
    // which is a static tool and has no way to catch a layout-only
    // runtime failure like this one). `IntrinsicHeight` solves this by
    // measuring each child's *natural* height in a first pass, then
    // handing `stretch` that concrete number to stretch everyone to.
    // See `_ToggleActionButton`'s own `mainAxisAlignment: center` for
    // the other half of this: without it, a button given extra height
    // this way would leave its icon and label stuck at the top instead
    // of centered in the taller box.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _ToggleActionButton(
              icon: isFavorite ? Icons.star : Icons.star_border,
              label: 'Favoritar',
              active: isFavorite,
              activeColor: AppColors.favorite,
              activeBackground: AppColors.favoriteTint,
              activeBorder: AppColors.favoriteBorder,
              onTap: onToggleFavorite,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _ToggleActionButton(
              icon: Icons.bedtime,
              label: sleepMinutes > 0 ? 'Dormir ${sleepMinutes}min' : 'Dormir',
              active: sleepMinutes > 0 || sleepPanelOpen,
              activeColor: AppColors.primary,
              activeBackground: AppColors.primaryTint,
              activeBorder: AppColors.primary,
              onTap: onToggleSleepPanel,
            ),
          ),
        ],
      ),
    );
  }
}

class _ToggleActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final Color activeColor;
  final Color activeBackground;
  final Color activeBorder;
  final VoidCallback? onTap;

  const _ToggleActionButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.activeColor,
    required this.activeBackground,
    required this.activeBorder,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? activeColor : AppColors.textSecondary;
    return Material(
      color: active ? activeBackground : AppColors.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: active ? activeBorder : AppColors.border, width: 1.5),
          ),
          // `center`, not the default `start`: `ActionButtonsRow` stretches
          // all three buttons to a shared height (see its own doc), which
          // can leave this Column with more height than its icon+label
          // actually need. Centering keeps the content in the middle of
          // that extra space instead of stuck at the top with blank space
          // below — this Column no longer decides the button's height on
          // its own, only how its content sits within whatever height it's
          // given.
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 21),
              const SizedBox(height: 4),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
