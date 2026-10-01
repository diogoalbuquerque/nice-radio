// Resolves "what Brazilian state is the user in" from the device's GPS
// position, so the app can show only local stations without the user
// ever typing anything.
//
// WHY this is allowed to fail quietly at every step (permission denied,
// GPS unavailable, reverse geocoding not supported, no match found) and
// just return `null`: this service is explicitly the *automatic* half of
// a two-path design. The manual state picker in Settings is the other
// half and is always available. A `null` here is a normal, expected outcome, not an error to
// surface to the user.
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import '../utils/brazilian_states.dart';

class LocationService {
  /// Returns one of [BrazilianStates.all]'s canonical names, or `null` if
  /// it could not be determined for any reason.
  Future<String?> resolveBrazilianState() async {
    if (!await _hasLocationPermission()) return null;

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low, // we only need state-level precision
          timeLimit: Duration(seconds: 10),
        ),
      );

      // `geocoding` has no web implementation (it wraps each platform's
      // native geocoder, and browsers do not expose one) — on Flutter Web
      // this throws, which we treat the same as "could not resolve" and
      // fall back to manual selection, exactly per the documented design.
      final placemarks = await Geocoding().placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (placemarks.isEmpty) return null;

      return BrazilianStates.normalize(placemarks.first.administrativeArea);
    } catch (_) {
      return null;
    }
  }

  Future<bool> _hasLocationPermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }
}
