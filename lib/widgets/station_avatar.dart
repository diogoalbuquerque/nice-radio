// The small square "logo" shown next to a station's name, both on the
// home screen and in the station list.
//
// WHY this is a shared widget instead of copy-pasted markup in both
// screens: it was literally duplicated during the design mockup phase
// (once per screen, because the mockup format required one self-contained
// file per screen). Real Flutter code has no such constraint, so here it
// is written once and both screens just place it with a different `size`.
import 'package:flutter/material.dart';

import '../models/radio_station.dart';

class StationAvatar extends StatelessWidget {
  final RadioStation station;
  final double size;

  const StationAvatar({super.key, required this.station, this.size = 48});

  @override
  Widget build(BuildContext context) {
    final radius = size * 0.22;
    final fallback = _InitialsBox(station: station, size: size, radius: radius);

    if (station.faviconUrl == null) return fallback;

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.network(
        station.faviconUrl!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        // A broken/unreachable favicon URL is common enough in a
        // crowdsourced database that this is treated as an expected case,
        // not an error — we just fall back to the initials box instead of
        // leaving Flutter's default broken-image icon on screen.
        errorBuilder: (context, error, stackTrace) => fallback,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return fallback;
        },
      ),
    );
  }
}

class _InitialsBox extends StatelessWidget {
  final RadioStation station;
  final double size;
  final double radius;

  const _InitialsBox({required this.station, required this.size, required this.radius});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: station.avatarColor,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Text(
        station.initials,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: size * 0.32,
        ),
      ),
    );
  }
}
