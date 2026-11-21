// Wraps the `volume_controller` package so the rest of the app never
// touches its API directly.
//
// WHY the in-app volume buttons drive the phone's actual system volume
// instead of just the audio player's internal gain: this was an
// explicit, deliberate product decision for the app's target audience.
// Most phone apps already have a volume the user understands — the one
// controlled by the hardware buttons on the side of the phone. A second,
// separate "app volume" that behaves differently (e.g. capped by the
// system volume, or needing the hardware buttons turned all the way up
// first) is a common source of "why can't I hear it" confusion. By
// controlling the same system volume the hardware buttons control, the
// in-app +/- buttons and the phone's physical buttons always agree, and
// [showSystemUI] is left at its default `true` so the OS's own volume
// overlay appears too — reinforcing that this really is "the phone's
// volume", not some separate app-only setting.
//
// WHY every platform call here first checks [kIsWeb], then is *also*
// wrapped in try/catch: `volume_controller` only ships native
// implementations for Android, iOS, macOS, Linux and Windows — there is
// no browser API for "the system volume", so it has no web
// implementation at all. Calling it there would either throw
// synchronously or, worse, deliver an error asynchronously on its event
// stream where a plain try/catch cannot catch it. Checking [kIsWeb]
// avoids ever making the call in the one case known to always fail; the
// try/catch around what remains covers everything else this class
// cannot enumerate in advance (a supported OS that still denies the
// permission, a test environment with no platform channel registered,
// and so on). Either way, a failure here is treated the same way
// `LocationService` treats a failed GPS lookup: quietly, with a
// reasonable fallback, never a crash.
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:volume_controller/volume_controller.dart';

class SystemVolumeService {
  /// Used when the platform cannot report a real volume (e.g. running on
  /// web) — matches [PlayerState.initial]'s own placeholder, so a
  /// platform without volume support just keeps that starting value.
  static const _fallbackPercent = 60;

  final VolumeController _controller = VolumeController.instance;

  /// Current system volume as a 0–100 integer percentage, or
  /// [_fallbackPercent] if this platform has no system volume to read.
  Future<int> getVolumePercent() async {
    if (kIsWeb) return _fallbackPercent;
    try {
      final volume = await _controller.getVolume();
      return _toPercent(volume);
    } catch (_) {
      return _fallbackPercent;
    }
  }

  /// iOS's hardware buttons move the volume in 16 equal steps (6.25%).
  static const _iosSteps = 16;

  /// Moves the system volume by exactly one press of the phone's own volume
  /// buttons ([direction] +1 up, -1 down), so the in-app +/- and the hardware
  /// buttons always move the same amount. Android: `adjustStreamVolume` in
  /// `MainActivity.kt` (the very call the hardware button makes; the number of
  /// steps varies by phone). iOS: one of [_iosSteps]. The listener reports the
  /// result.
  Future<void> stepVolume(int direction) async {
    if (kIsWeb) return;
    try {
      if (Platform.isAndroid) {
        await const MethodChannel('com.nice.radio/volume').invokeMethod('adjust', direction);
      } else {
        await _controller.setVolume(stepOnScale(await _controller.getVolume(), direction, _iosSteps));
      }
    } catch (_) {
      // Nothing to fall back to; the listener keeps the shown value honest.
    }
  }

  /// [volume] (0–1) snapped to the nearest of [steps] notches, moved by
  /// [direction] notches and clamped.
  static double stepOnScale(double volume, int direction, int steps) =>
      ((volume * steps).round() + direction).clamp(0, steps) / steps;

  /// Notifies [onChanged] whenever the system volume changes — including
  /// when the user presses the phone's physical volume buttons while the
  /// app is open, so the on-screen percentage never falls out of sync
  /// with the real, single volume it is meant to represent. Does nothing
  /// on a platform without system volume support.
  ///
  /// WHY `fetchInitialVolume: false`: the caller (`PlayerNotifier.build`)
  /// already reads the starting volume once, explicitly, via
  /// [getVolumePercent] before attaching this listener — an immediate
  /// duplicate callback here would just mean setting the same state
  /// twice for no reason.
  void listen(void Function(int percent) onChanged) {
    if (kIsWeb) return;
    try {
      _controller.addListener(
        (volume) => onChanged(_toPercent(volume)),
        fetchInitialVolume: false,
      );
    } catch (_) {
      // No system volume to listen to on this platform.
    }
  }

  Future<void> dispose() async {
    if (kIsWeb) return;
    try {
      await _controller.removeListener();
    } catch (_) {
      // Nothing was ever successfully listening — nothing to tear down.
    }
  }

  int _toPercent(double volume) => (volume.clamp(0.0, 1.0) * 100).round();
}
