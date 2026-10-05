// Wraps Firebase Analytics: every method here is one named event this app
// actually cares about (which buttons get tapped, which station starts
// playing, which state gets picked, which screen is open) — kept as one
// named method per event instead of callers building a raw
// Map<String, Object> by hand at every call site, so an event/parameter
// name typo is caught here once instead of scattered across the app.
//
// WHY the provider for this service lives in this file, unlike every
// other `*ServiceProvider` in this app (which live in whichever
// `providers/*.dart` file or `main.dart` happens to be their main
// consumer): analytics is used from almost everywhere — every screen,
// `player_provider.dart`, `settings_provider.dart` — so there is no
// single "main consumer" file to attach it to without either an
// arbitrary choice or a real risk of a circular import (e.g. a screen
// importing `main.dart` back to reach a provider defined there). Keeping
// the provider next to the class it wraps sidesteps both problems.
//
// WHY every method here is wrapped in try/catch and silently swallows
// failure: analytics must never be able to break the app's actual
// functionality (playing a station, saving a favorite) just because a
// network call to Firebase failed, or the SDK isn't initialized in a
// test/web environment — see `main.dart`'s own note on Firebase being
// skipped entirely on web, and `QuickActionsService`'s near-identical
// "degrades quietly" reasoning for platforms/environments it can't
// predict ahead of time.
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/radio_station.dart';

/// Shared instance of [AnalyticsService] — same reasoning as every other
/// `*ServiceProvider` in this app: lets tests substitute a fake without
/// touching the real Firebase SDK.
final analyticsServiceProvider = Provider<AnalyticsService>((ref) {
  return AnalyticsService();
});

class AnalyticsService {
  // A getter, not a `final` field: `FirebaseAnalytics.instance` throws
  // immediately if `Firebase.initializeApp()` never ran (web, a test —
  // see `main.dart`'s own note on where that happens/doesn't) — a plain
  // field initializer would run that lookup the moment this class is
  // constructed, outside every method's own try/catch below, and take
  // down whatever was building this service with it. A getter defers the
  // lookup to each call site, where it's already inside the try block.
  FirebaseAnalytics get _analytics => FirebaseAnalytics.instance;

  /// Call once per screen, right when it first becomes visible — this is
  /// what lets Firebase's own "Engagement" report show which screens
  /// people actually spend time on (it computes that from consecutive
  /// `screen_view` events plus the time between them; there is no manual
  /// timer to write or maintain here).
  Future<void> logScreenView(String screenName) async {
    try {
      await _analytics.logScreenView(screenName: screenName);
    } catch (_) {
      // No network, Firebase not initialized (web, a test), etc.
    }
  }

  /// A named, non-navigational tap — the play/pause button, favorite
  /// star, night-mode lamp, a sleep-timer option, the refresh icon, and
  /// so on. [buttonName] should be a short, stable, snake_case identifier
  /// — see call sites for the actual names in use. [screen] says where the
  /// tap happened, for buttons that exist on more than one screen (the
  /// Favoritas/Todas toggle, the favorite star).
  Future<void> logButtonTap(String buttonName, {String? screen}) async {
    try {
      await _analytics.logEvent(
        name: 'button_tap',
        parameters: {'button_name': buttonName, 'screen': ?screen},
      );
    } catch (_) {}
  }

  /// One continuous stretch of listening to one station, fired when it ends
  /// (pause, station switch). This is the only measure of time spent
  /// *listening*: `screen_view` only counts the screen being open, and the
  /// app is mostly used with the screen off.
  Future<void> logListeningSession(RadioStation station, int seconds) async {
    try {
      await _analytics.logEvent(
        name: 'listening_session',
        parameters: {'station_id': station.id, 'station_name': station.name, 'seconds': seconds},
      );
    } catch (_) {}
  }

  /// Fired every time a station actually starts loading. Deliberately
  /// called from the single choke point every station selection passes
  /// through — `PlayerNotifier.playStation` — so this covers a station
  /// picked from the list, "avançar"/"voltar", the lock-screen
  /// notification, Android Auto, and the home-screen quick action/widget,
  /// all with this one call site, instead of needing one at each of
  /// those entry points individually.
  Future<void> logStationPlayed(RadioStation station) async {
    try {
      await _analytics.logEvent(
        name: 'station_played',
        parameters: {'station_id': station.id, 'station_name': station.name},
      );
    } catch (_) {}
  }

  /// Fired every time a Brazilian state is selected — called from
  /// `SettingsNotifier.selectState`, the single choke point both the
  /// automatic GPS-resolved guess on first launch and a manual pick in
  /// Configurações already go through.
  Future<void> logStateSelected(String state) async {
    try {
      await _analytics.logEvent(name: 'state_selected', parameters: {'state': state});
    } catch (_) {}
  }
}

/// Shorthand for the most common call site: a tap handler logging its button.
extension AnalyticsTap on WidgetRef {
  void trackTap(String buttonName, {String? screen}) =>
      read(analyticsServiceProvider).logButtonTap(buttonName, screen: screen);
}
