import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The "modo noturno" toggle's icon: one lamp shape (`Icons.lightbulb`)
/// for both states, with seven short rays drawn radially above/around
/// it only when [lit] — so "on" and "off" are guaranteed to share the
/// exact same bulb silhouette and orientation, never two unrelated
/// glyphs that happen to both look vaguely like a bulb (an earlier
/// version paired `Icons.wb_incandescent`, a *different* icon family
/// with its own proportions, for "on" with `Icons.lightbulb_outline`
/// for "off" — visually wrong once compared side by side, since the two
/// glyphs don't actually share an orientation). The current ray layout
/// and filled-bulb style were matched by hand to a reference icon the
/// user supplied; there is no built-in Material icon that pairs a
/// ray-less bulb with a matching lit one sharing the same base glyph,
/// so the rays are drawn here instead, positioned by simple trigonometry
/// (see [_rayAngles]) rather than seven hand-picked offsets, so the
/// spacing stays even if the radius/length/thickness constants below
/// are ever retuned.
class LampIcon extends StatelessWidget {
  final bool lit;
  final Color color;

  const LampIcon({super.key, required this.lit, required this.color});

  // Clockwise degrees from straight up, one ray every 45° except at the
  // very bottom (180°) — that's where the bulb's own base sits, so a
  // ray there would just be drawn through it. Matches the reference
  // icon the user supplied.
  static const _rayAngles = [0, 45, 90, 135, 225, 270, 315];

  @override
  Widget build(BuildContext context) {
    const box = 22.0;
    const center = box / 2;
    const bulbSize = 15.0;
    const rayRadius = 9.5;
    const rayLength = 5.0;
    const rayThickness = 2.2;

    return SizedBox(
      width: box,
      height: box,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: center - bulbSize / 2,
            top: center - bulbSize / 2 + 1,
            child: Icon(Icons.lightbulb, size: bulbSize, color: color),
          ),
          if (lit)
            for (final deg in _rayAngles)
              _ray(
                color,
                angleDeg: deg.toDouble(),
                center: center,
                radius: rayRadius,
                length: rayLength,
                thickness: rayThickness,
              ),
        ],
      ),
    );
  }

  Widget _ray(
    Color color, {
    required double angleDeg,
    required double center,
    required double radius,
    required double length,
    required double thickness,
  }) {
    final rad = angleDeg * math.pi / 180;
    final dx = radius * math.sin(rad);
    final dy = -radius * math.cos(rad);
    return Positioned(
      left: center + dx - length / 2,
      top: center + dy - thickness / 2,
      child: Transform.rotate(
        angle: rad,
        child: Container(
          width: length,
          height: thickness,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(thickness / 2)),
        ),
      ),
    );
  }
}
