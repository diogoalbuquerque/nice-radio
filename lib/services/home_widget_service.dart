// Bridges to the native home-screen widget on Android and iOS: pushes
// the current station/song/playing state out to it, and relays taps on
// its play/pause and skip buttons back into this app.
//
// WHY hand-rolled platform channels instead of a pub.dev package (e.g.
// `home_widget`): the widget's buttons need to control playback that is
// already running — on Android, that means routing straight into
// `audio_service`'s existing MediaSession the same way a Bluetooth
// headset button already does, not spinning up a second, separate
// control path. That native wiring is app-specific regardless of which
// package writes the shared display data, so a package would only have
// covered a small, simple part of this (a few strings in shared
// storage) while adding a real dependency-version surface of its own —
// not worth it for two `MethodChannel` calls' worth of code.
//
// WHY every call here is wrapped defensively: this channel only has a
// native implementation on Android and iOS (see `MainActivity.kt` and
// `AppDelegate.swift`) — same reasoning as `QuickActionsService`/
// `SystemVolumeService` for why every call is guarded rather than
// assumed to succeed.
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

/// The action names the native widget sends back — kept as constants so
/// a typo in either this file or the native side (`MainActivity.kt`/
/// `AppDelegate.swift`) shows up as "nothing happens" during testing
/// rather than a silent mismatch nobody notices until later.
class HomeWidgetAction {
  static const playPause = 'playPause';
  static const next = 'next';
  static const previous = 'previous';
}

class HomeWidgetService {
  static const _channel = MethodChannel('com.nice.radio/home_widget');

  /// Pushes the latest playback info to the native widget and asks the OS
  /// to redraw it. Called on every station/title/play-state change — see
  /// `main.dart`'s `_HomeWidgetSync` for where that's decided. Safe to
  /// call often: the native side only actually redraws when something
  /// changed (see `NiceRadioWidgetProvider.kt`'s own note on this).
  Future<void> updateNowPlaying({
    required String stationName,
    String? songTitle,
    required bool isPlaying,
    Uint8List? artworkPng,
  }) async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod('updateNowPlaying', {
        'stationName': stationName,
        'songTitle': songTitle,
        'isPlaying': isPlaying,
        'artworkPng': artworkPng,
      });
    } catch (_) {
      // No home-screen widget support on this platform/environment.
    }
  }

  /// Registers [onAction] to run when a widget button is tapped. Only
  /// ever actually invoked on iOS — Android's widget buttons target its
  /// `MediaButtonReceiver` directly and never round-trip through Dart at
  /// all (see `NiceRadioWidgetProvider.kt`'s own WHY comment) — but the
  /// handler is registered on both platforms for symmetry, in case a
  /// future Android change ever needs the same path.
  void setActionHandler(Future<void> Function(String action) onAction) {
    if (kIsWeb) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'widgetAction') {
        await onAction(call.arguments as String);
      }
    });
  }
}
