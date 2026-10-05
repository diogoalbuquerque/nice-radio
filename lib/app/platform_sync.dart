// Whole-session wrappers that connect the player to platform surfaces. Each
// owns exactly one concern so `PlayerNotifier` never has to know how a
// platform delivers lifecycle events, shortcuts or widget taps.
//
// They must live ABOVE the screens, inside the app's single route: replacing
// that route (e.g. `Navigator.pushReplacement` after onboarding) destroyed
// their `State` and every `ref.listen`/`WidgetsBindingObserver`, silently
// stopping widget updates until the next cold start. See `_StartupGate` in
// `main.dart`.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/radio_station.dart';
import '../providers/platform_services_provider.dart';
import '../providers/player_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/stations_provider.dart';
import '../providers/voice_commands_provider.dart';
import '../services/home_widget_service.dart';
import '../utils/brazilian_states.dart';

/// Tells the player every time the app returns to the foreground (iOS
/// lock-screen controls fix; see `PlayerNotifier.handleAppResumed`).
class AppLifecycleSync extends ConsumerStatefulWidget {
  final Widget child;

  const AppLifecycleSync({super.key, required this.child});

  @override
  ConsumerState<AppLifecycleSync> createState() => _AppLifecycleSyncState();
}

class _AppLifecycleSyncState extends ConsumerState<AppLifecycleSync> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(playerProvider.notifier).handleAppResumed();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Keeps the home-screen widget (Android App Widget / iOS WidgetKit) in sync
/// with playback in both directions: pushes station/song/play-state out when
/// they change, and relays taps on its buttons to the same `PlayerNotifier`
/// actions the screen and lock screen use.
class HomeWidgetSync extends ConsumerStatefulWidget {
  final Widget child;

  const HomeWidgetSync({super.key, required this.child});

  @override
  ConsumerState<HomeWidgetSync> createState() => _HomeWidgetSyncState();
}

class _HomeWidgetSyncState extends ConsumerState<HomeWidgetSync> {
  // The three values the widget shows, compared by hand so an unrelated
  // `PlayerState` change (volume, ...) sends nothing.
  String? _lastStationId;
  String? _lastTitle;
  bool? _lastPlaying;

  // The logo depends only on the station, so it is resolved once per station
  // and resent as-is on title/play-state updates.
  String? _artworkStationId;
  Uint8List? _artworkBytes;

  // Generation counter: the artwork fetch (up to 5s) can finish after a newer
  // update; a superseded call is discarded instead of pushing stale data.
  int _updateGeneration = 0;

  @override
  void initState() {
    super.initState();
    ref.read(homeWidgetServiceProvider).setActionHandler((action) async {
      final notifier = ref.read(playerProvider.notifier);
      switch (action) {
        case HomeWidgetAction.playPause:
          await notifier.togglePlayPause();
        case HomeWidgetAction.next:
          await notifier.playNext();
        case HomeWidgetAction.previous:
          await notifier.playPrevious();
      }
    });
  }

  Future<void> _pushUpdate(PlayerState next) async {
    final station = next.currentStation;
    if (station == null) return;

    final title = next.nowPlayingTitle;
    if (station.id == _lastStationId && title == _lastTitle && next.isPlaying == _lastPlaying) return;
    _lastStationId = station.id;
    _lastTitle = title;
    _lastPlaying = next.isPlaying;

    final generation = ++_updateGeneration;

    if (station.id != _artworkStationId) {
      _artworkBytes = await ref.read(stationArtworkServiceProvider).logoBytes(station);
      _artworkStationId = station.id;
    }

    if (!mounted || generation != _updateGeneration) return;
    await ref.read(homeWidgetServiceProvider).updateNowPlaying(
          stationName: station.name,
          songTitle: title,
          isPlaying: next.isPlaying,
          artworkPng: _artworkBytes,
        );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<PlayerState>(playerProvider, (previous, next) => unawaited(_pushUpdate(next)));
    return widget.child;
  }
}

/// Wires the launcher/Siri entry points to the player: the "Tocar rádio atual"
/// icon shortcut (kept labeled with the current station), and Siri/Shortcuts/
/// Assistant voice commands plus the iOS station list they pick from. Both
/// also deliver the action that *launched* the app, so no cold-start special
/// case is needed.
class QuickActionsSync extends ConsumerStatefulWidget {
  final Widget child;

  const QuickActionsSync({super.key, required this.child});

  @override
  ConsumerState<QuickActionsSync> createState() => _QuickActionsSyncState();
}

class _QuickActionsSyncState extends ConsumerState<QuickActionsSync> {
  String? _lastShortcutStationId;

  @override
  void initState() {
    super.initState();
    ref.read(quickActionsServiceProvider).initialize(
          () => ref.read(playerProvider.notifier).playFromQuickAction(),
        );
    ref.read(voiceCommandServiceProvider).initialize(
          (command) => ref.read(voiceCommandHandlerProvider).handle(command),
        );
  }

  @override
  Widget build(BuildContext context) {
    // Keeps Siri/Shortcuts' station list in step with the state's stations
    // (iOS only; a no-op elsewhere).
    ref.listen<AsyncValue<List<RadioStation>>>(stationsProvider, (previous, next) {
      final stations = next.value;
      if (stations != null && stations.isNotEmpty) {
        final stateName = ref.read(settingsProvider).value?.selectedState;
        final abbreviation = BrazilianStates.all.where((uf) => uf.name == stateName).firstOrNull?.abbreviation;
        ref.read(voiceCommandServiceProvider).cacheStations(stations, stateAbbreviation: abbreviation);
      }
    });

    // By id (RadioStation has no `==`): re-register the shortcut only when the
    // station actually changes.
    ref.listen<PlayerState>(playerProvider, (previous, next) {
      final stationId = next.currentStation?.id;
      if (stationId == _lastShortcutStationId) return;
      _lastShortcutStationId = stationId;
      ref.read(quickActionsServiceProvider).updateShortcut(next.currentStation);
    });

    return widget.child;
  }
}
