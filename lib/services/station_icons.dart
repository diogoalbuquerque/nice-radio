// Station logos bundled into the app (`assets/station_icons/<station id>.png`),
// filled by `tool/fetch_station_icons.py` before a release build. A station
// without one keeps the old behavior: network favicon, else coloured initials.
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

String bundledIconPath(String stationId) => 'assets/station_icons/$stationId.png';

/// Station ids that have a bundled logo, read once from the asset manifest
/// (so a missing asset is never requested).
final bundledIconIdsProvider = FutureProvider<Set<String>>((ref) async {
  final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
  final ids = <String>{};
  for (final asset in manifest.listAssets()) {
    final match = RegExp(r'^assets/station_icons/(.+)\.png$').firstMatch(asset);
    if (match != null) ids.add(match.group(1)!);
  }
  return ids;
});
