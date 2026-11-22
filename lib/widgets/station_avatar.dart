// The small square "logo" shown next to a station's name, both on the
// home screen and in the station list.
//
// WHY this is a shared widget instead of copy-pasted markup in both
// screens: it was literally duplicated during the design mockup phase
// (once per screen, because the mockup format required one self-contained
// file per screen). Real Flutter code has no such constraint, so here it
// is written once and both screens just place it with a different `size`.
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/radio_station.dart';
import '../providers/platform_services_provider.dart';

/// A station logo downloaded once to the device (see
/// `StationArtworkService.cachedLogoFile`), keyed by its URL so every avatar of
/// the same station shares one download. `null` = no logo (initials are shown).
final stationLogoFileProvider = FutureProvider.family<File?, String>((ref, url) {
  return ref.read(stationArtworkServiceProvider).cachedLogoFile(url);
});

class StationAvatar extends ConsumerWidget {
  final RadioStation station;
  final double size;

  const StationAvatar({super.key, required this.station, this.size = 48});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final radius = size * 0.22;
    final fallback = _InitialsBox(station: station, size: size, radius: radius);

    if (station.faviconUrl == null) return fallback;

    // Web has no file system; the browser's HTTP cache keeps the logo instead
    // (the CDN marks logo files immutable).
    final Widget image;
    if (kIsWeb) {
      image = Image.network(station.faviconUrl!, width: size, height: size, fit: BoxFit.cover,
          errorBuilder: (_, _, _) => fallback);
    } else {
      // Initials while it downloads, and for good when it can't be fetched.
      final file = ref.watch(stationLogoFileProvider(station.faviconUrl!)).value;
      if (file == null) return fallback;
      image = Image.file(file, width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback);
    }
    return ClipRRect(borderRadius: BorderRadius.circular(radius), child: image);
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
