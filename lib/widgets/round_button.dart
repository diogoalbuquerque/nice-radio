import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A small circular, bordered icon button — the header icons (settings,
/// modo noturno), the volume +/- buttons, and the previous/next transport
/// buttons on the home screen are all this same widget, just at different
/// sizes. Pulled out of `home_screen.dart` after noticing two near-copies
/// of it (`_CircleIconButton` and `_RoundButton`) existed there.
class RoundButton extends StatelessWidget {
  final IconData? icon;
  // Used instead of [icon] when the button needs something a single
  // IconData can't express — see LampIcon, whose "on"/"off" states are
  // the same bulb glyph with small rays added or removed, not two
  // different built-in icons (see its own doc for why that matters).
  final Widget? iconWidget;
  final Color? color;
  final String tooltip;
  // Drives the default icon size/padding below (`size * 0.45`/`size * 0.2`)
  // for the transport/volume buttons, which come in several different
  // sizes. [iconSize]/[padding] override that scaling directly for
  // buttons — like the header icons — tuned to an exact look instead.
  final double size;
  final double? iconSize;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  const RoundButton({
    super.key,
    this.icon,
    this.iconWidget,
    this.color,
    required this.tooltip,
    this.size = 44,
    this.iconSize,
    this.padding,
    required this.onTap,
  }) : assert(icon != null || iconWidget != null, 'Provide either icon or iconWidget');

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      shape: CircleBorder(side: BorderSide(color: AppColors.border, width: 1.5)),
      child: IconButton(
        icon: iconWidget ?? Icon(icon, color: color),
        tooltip: tooltip,
        iconSize: iconSize ?? size * 0.45,
        padding: padding ?? EdgeInsets.all(size * 0.2),
        onPressed: onTap,
      ),
    );
  }
}
