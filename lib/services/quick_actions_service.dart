// Wraps the `quick_actions` package: the shortcut menu that appears when
// the user long-presses (Android) or force-touches / long-presses (iOS)
// the app's home-screen icon.
//
// WHY this app only ever has one shortcut item ("Tocar rádio atual"),
// never a list: the whole point is a shortcut an elderly user can act on
// without opening the app or reading a menu — one clearly-labeled action
// naming the actual station serves that better than a menu of options to
// choose between.
//
// WHY every call here checks [kIsWeb] first: `quick_actions` only ships
// native implementations for Android and iOS — there is no "home screen"
// on the web for a shortcut to live on, so it has no web implementation
// at all, and calling it there would throw. The try/catch around what
// remains covers everything [kIsWeb] cannot predict (a test environment
// with no platform channel registered, for instance) — see
// `SystemVolumeService`'s near-identical reasoning.
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:quick_actions/quick_actions.dart';

import '../models/radio_station.dart';

class QuickActionsService {
  /// Arbitrary but stable identifier for the one shortcut this app has.
  /// Matched against in the handler passed to [initialize].
  static const playCurrentStationType = 'play_current_station';

  final QuickActions _quickActions = const QuickActions();

  /// Registers [onPlayCurrentStation] to run when the shortcut is tapped
  /// — whether the app was already running or was fully closed and this
  /// tap is what launched it. Call once, early (see `main.dart`). A no-op
  /// on platforms without a home-screen shortcut to tap in the first
  /// place.
  Future<void> initialize(Future<void> Function() onPlayCurrentStation) async {
    if (kIsWeb) return;
    try {
      await _quickActions.initialize((type) {
        if (type == playCurrentStationType) {
          onPlayCurrentStation();
        }
      });
    } catch (_) {
      // No shortcut support on this platform/environment.
    }
  }

  /// Updates the shortcut to name [station], or removes it entirely when
  /// [station] is `null` (nothing to resume yet — e.g. before the user
  /// has ever picked a station). Call this whenever the current/last
  /// station changes; see `main.dart`'s listener on `playerProvider`.
  Future<void> updateShortcut(RadioStation? station) async {
    if (kIsWeb) return;
    try {
      if (station == null) {
        await _quickActions.clearShortcutItems();
        return;
      }

      await _quickActions.setShortcutItems([
        ShortcutItem(
          type: playCurrentStationType,
          localizedTitle: 'Tocar rádio atual',
          localizedSubtitle: station.name,
          // Android looks this up by name in res/drawable (and R8 would
          // strip it unless res/raw/keep.xml keeps it). Unset, the
          // launcher shows its default robot icon. iOS ignores unknown
          // names, so no icon there.
          icon: 'ic_shortcut_play',
        ),
      ]);
    } catch (_) {
      // No shortcut support on this platform/environment.
    }
  }
}
