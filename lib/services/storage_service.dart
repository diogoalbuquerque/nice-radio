// Thin wrapper around SharedPreferences (a simple on-device key-value
// store) for everything Nice Radio needs to remember between app
// launches: favorite stations, the chosen state, and the data-usage
// counter.
//
// WHY a wrapper instead of calling SharedPreferences directly from the
// providers: it keeps every raw string key in exactly one place. Without
// this, a typo in a key string (e.g. "favorite_ids" in one file and
// "favoriteIds" in another) would silently fail to persist — a classic,
// hard-to-spot bug class. It also means a future switch to a different
// storage mechanism (e.g. if the app ever needs something more than
// key-value) only touches this one file.
//
// SECURITY NOTE: everything stored here is non-sensitive (a list of
// station ids, a state name, a byte counter). There is no user account,
// password, or personal data in this app, so plain-text local storage is
// appropriate — no encryption is needed. If a future version adds
// anything sensitive, it should go through `flutter_secure_storage`
// instead of this file.
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/radio_station.dart';

class StorageService {
  static const _keyFavoriteIds = 'favorite_station_ids';
  static const _keySelectedState = 'selected_state';
  static const _keyDataUsedBytes = 'data_used_bytes';
  static const _keyDataUsedSince = 'data_used_since_iso8601';
  static const _keyOnboardingDone = 'onboarding_done';
  static const _keyLastStation = 'last_station_json';
  static const _keyDarkModeEnabled = 'dark_mode_enabled';
  static const _keySuppressOfflineWarning = 'suppress_offline_warning';
  static const _keyViewModeFavorites = 'view_mode_favorites';
  static const _keyBrowsableStations = 'browsable_stations_json';

  // Every method below starts by awaiting this. Pulled into one getter
  // instead of repeating `SharedPreferences.getInstance()` at the top of
  // each of them — purely a readability/consistency win, not a
  // performance one: the package itself already caches the underlying
  // instance internally after the first call.
  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<Set<String>> getFavoriteIds() async {
    final prefs = await _prefs;
    return (prefs.getStringList(_keyFavoriteIds) ?? const []).toSet();
  }

  Future<void> setFavoriteIds(Set<String> ids) async {
    final prefs = await _prefs;
    await prefs.setStringList(_keyFavoriteIds, ids.toList());
  }

  Future<String?> getSelectedState() async {
    final prefs = await _prefs;
    return prefs.getString(_keySelectedState);
  }

  Future<void> setSelectedState(String state) async {
    final prefs = await _prefs;
    await prefs.setString(_keySelectedState, state);
  }

  Future<int> getDataUsedBytes() async {
    final prefs = await _prefs;
    return prefs.getInt(_keyDataUsedBytes) ?? 0;
  }

  Future<void> setDataUsedBytes(int bytes) async {
    final prefs = await _prefs;
    await prefs.setInt(_keyDataUsedBytes, bytes);
  }

  Future<DateTime> getDataUsedSince() async {
    final prefs = await _prefs;
    final raw = prefs.getString(_keyDataUsedSince);
    return raw != null ? DateTime.tryParse(raw) ?? DateTime.now() : DateTime.now();
  }

  Future<void> setDataUsedSince(DateTime date) async {
    final prefs = await _prefs;
    await prefs.setString(_keyDataUsedSince, date.toIso8601String());
  }

  Future<bool> getOnboardingDone() async {
    final prefs = await _prefs;
    return prefs.getBool(_keyOnboardingDone) ?? false;
  }

  Future<void> setOnboardingDone(bool done) async {
    final prefs = await _prefs;
    await prefs.setBool(_keyOnboardingDone, done);
  }

  /// The station the app was last playing (or had selected), so the
  /// home-screen icon's "Tocar rádio atual" quick action has something to
  /// resume even after the app was fully closed — see
  /// `PlayerNotifier._persistLastStation` for where this is written, and
  /// `main.dart`'s quick-action handler for where it is read back.
  Future<RadioStation?> getLastStation() async {
    final prefs = await _prefs;
    final raw = prefs.getString(_keyLastStation);
    if (raw == null) return null;
    try {
      return RadioStation.fromCache(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // Corrupt or stale (pre-migration) cache entry — treat it the same
      // as "nothing saved yet" rather than crashing app startup over it.
      return null;
    }
  }

  Future<void> setLastStation(RadioStation station) async {
    final prefs = await _prefs;
    await prefs.setString(_keyLastStation, jsonEncode(station.toJson()));
  }

  /// The station list the lock screen and Android Auto browse, saved with the
  /// state it belongs to so a cold start (a car binding the service before the
  /// first fetch finishes, or no network) still has stations to show. Written
  /// each time a fresh non-empty list arrives; see
  /// `PlayerNotifier._loadCachedBrowsableStations` for where it is read.
  Future<void> setBrowsableStations(String state, List<RadioStation> stations) async {
    final prefs = await _prefs;
    await prefs.setString(
      _keyBrowsableStations,
      jsonEncode({'state': state, 'stations': [for (final s in stations) s.toJson()]}),
    );
  }

  /// The saved list, only if it was saved for [state] — never another state's.
  /// `null` when nothing usable is stored (absent, corrupt, other state, empty).
  Future<List<RadioStation>?> getBrowsableStations(String state) async {
    final prefs = await _prefs;
    final raw = prefs.getString(_keyBrowsableStations);
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      if (map['state'] != state) return null;
      final stations = <RadioStation>[
        for (final item in map['stations'] as List)
          ?RadioStation.fromCache(item as Map<String, dynamic>),
      ];
      return stations.isEmpty ? null : stations;
    } catch (_) {
      // Corrupt or from an older app version: same as "nothing saved".
      return null;
    }
  }

  /// "Modo noturno" — a manual, explicit toggle rather than something that
  /// follows the system theme. See the WHY comment on `buildAppTheme` in
  /// `app_theme.dart` for the reasoning (in short: light-on-dark text can
  /// be *harder*, not easier, to read through some forms of cataracts, so
  /// this app never guesses — the person decides).
  Future<bool> getDarkModeEnabled() async {
    final prefs = await _prefs;
    return prefs.getBool(_keyDarkModeEnabled) ?? false;
  }

  Future<void> setDarkModeEnabled(bool enabled) async {
    final prefs = await _prefs;
    await prefs.setBool(_keyDarkModeEnabled, enabled);
  }

  /// Whether the "algumas estações estão fora do ar" dialog (shown after
  /// 3 consecutive failed connection attempts — see
  /// `PlayerNotifier._setPlaybackError`) has been suppressed by the user
  /// via that dialog's own "Não mostrar novamente" checkbox. Defaults to
  /// false so the dialog is free to show the first time it's earned; the
  /// checkbox comes pre-checked in the dialog itself (see
  /// `StationsOfflineDialog`), so most people who just dismiss it without
  /// touching the checkbox end up suppressing it from that point on —
  /// only someone who explicitly unchecks it keeps seeing it every 3
  /// failures.
  Future<bool> getSuppressOfflineWarning() async {
    final prefs = await _prefs;
    return prefs.getBool(_keySuppressOfflineWarning) ?? false;
  }

  Future<void> setSuppressOfflineWarning(bool suppress) async {
    final prefs = await _prefs;
    await prefs.setBool(_keySuppressOfflineWarning, suppress);
  }

  /// Whether the Favoritas/Todas toggle on the home screen (see
  /// `StationViewMode` in `stations_provider.dart`) was last left on
  /// "Favoritas", so reopening the app shows the same list the person
  /// had selected instead of always resetting to "Todas". Kept as a
  /// plain bool here, not the `StationViewMode` enum itself — this
  /// service must never import a `providers/` file (services sit *below* providers), so the
  /// enum-to-bool translation happens in `ViewModeNotifier` instead.
  Future<bool> getViewModeIsFavorites() async {
    final prefs = await _prefs;
    return prefs.getBool(_keyViewModeFavorites) ?? false;
  }

  Future<void> setViewModeIsFavorites(bool isFavorites) async {
    final prefs = await _prefs;
    await prefs.setBool(_keyViewModeFavorites, isFavorites);
  }
}
