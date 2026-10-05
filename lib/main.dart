// App entry point.
//
// WHY `ProviderScope` wraps everything: it is Riverpod's requirement —
// every provider in this app (settings, favorites, stations, the player)
// is only reachable from widgets underneath a ProviderScope. Forgetting
// it is a common first-run mistake, so it is called out here rather than
// left implicit.
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show PlatformDispatcher;

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'firebase_options.dart';
import 'providers/player_provider.dart';
import 'models/radio_station.dart';
import 'providers/settings_provider.dart';
import 'providers/stations_provider.dart';
import 'providers/voice_commands_provider.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/home_widget_service.dart';
import 'services/quick_actions_service.dart';
import 'services/station_artwork_service.dart';
import 'services/voice_command_service.dart';
import 'theme/app_theme.dart';
import 'utils/brazilian_states.dart';

/// Shared instance of [QuickActionsService]. WHY a provider for a plain
/// class with no state of its own: same reasoning as every other
/// `*ServiceProvider` in this app — lets tests substitute a fake without
/// touching the real platform APIs.
final quickActionsServiceProvider = Provider<QuickActionsService>((ref) {
  return QuickActionsService();
});

final voiceCommandServiceProvider = Provider<VoiceCommandService>((ref) {
  return VoiceCommandService();
});

/// Shared instance of [HomeWidgetService] — same reasoning as
/// [quickActionsServiceProvider] just above.
final homeWidgetServiceProvider = Provider<HomeWidgetService>((ref) {
  return HomeWidgetService();
});

/// Shared instance of [StationArtworkService] — same reasoning as
/// [quickActionsServiceProvider] just above.
final stationArtworkServiceProvider = Provider<StationArtworkService>((ref) {
  return StationArtworkService();
});

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase (Analytics + Crashlytics) is Android/iOS only — this app's
  // generated `firebase_options.dart` has no `web` entry (the web build
  // is a dev convenience for quickly seeing the app work, not a real
  // distribution target), and
  // firebase_crashlytics itself ships no web implementation to call in
  // the first place. Same "degrades quietly, not a bug to chase on web"
  // reasoning this app already applies to quick_actions/volume_controller.
  if (!kIsWeb) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

    // Routes every uncaught error into Crashlytics instead of just the
    // console. `recordFlutterFatalError`/`recordError` are Firebase's own
    // documented hooks for, respectively, an error the Flutter framework
    // itself catches (a bad build(), a failed layout) and one outside
    // Flutter's own error zone (a raw async error, a platform-channel
    // callback) — both need to be wired for crash reports to actually be
    // complete, not just the first kind.
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  }

  runApp(const ProviderScope(child: NiceRadioApp()));
}

class NiceRadioApp extends ConsumerWidget {
  const NiceRadioApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Narrowed with `select` so this root widget — and everything Flutter
    // would otherwise rebuild beneath it — only rebuilds when "modo
    // noturno" itself flips, not on every unrelated settings change (the
    // data-usage counter alone ticks every few seconds while playing).
    final darkModeEnabled = ref.watch(
      settingsProvider.select((async) => async.value?.darkModeEnabled ?? false),
    );
    final brightness = darkModeEnabled ? Brightness.dark : Brightness.light;

    return MaterialApp(
      title: 'Nice Radio',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(brightness),
      // Auto-logs a `screen_view` event on every `Navigator.push`/pop —
      // covers StationListScreen and SettingsScreen, since both are reached
      // that way. **Only for routes that carry a name**: the observer skips
      // a route whose `RouteSettings.name` is null, so every
      // `MaterialPageRoute` must be pushed with
      // `settings: RouteSettings(name: ...)` (it was not, and those two
      // screens were silently never reported). HomeScreen and OnboardingScreen are *not*
      // pushed routes (see `_StartupGate` below — they're a conditional
      // rebuild of `home:` itself), so those two log their own
      // `screen_view` by hand, in their `initState`.
      //
      // WHY `Firebase.apps.isNotEmpty`, not `!kIsWeb`: `kIsWeb` only
      // tells web apart from everything else — it says nothing about
      // whether `Firebase.initializeApp()` (see `main()`) actually ran,
      // which it never does under `flutter test` (tests call
      // `pumpWidget` directly, bypassing `main()` entirely). Reaching
      // for `FirebaseAnalytics.instance` there threw `[core/no-app]` and
      // took the whole widget test down with it. Checking whether an app
      // was actually initialized covers web *and* tests *and* any future
      // platform Firebase doesn't reach, with one condition instead of
      // an allowlist of environments to guess at ahead of time.
      navigatorObservers: Firebase.apps.isEmpty
          ? const []
          : [FirebaseAnalyticsObserver(analytics: FirebaseAnalytics.instance)],
      home: const _AppLifecycleSync(
        child: _HomeWidgetSync(child: _QuickActionsSync(child: _StartupGate())),
      ),
    );
  }
}

/// Notifies [PlayerNotifier] every time the app returns to the
/// foreground — see `PlayerNotifier.handleAppResumed`'s doc for the iOS
/// lock-screen-controls bug this exists to work around.
///
/// WHY a separate widget from [_QuickActionsSync] instead of folding
/// this one extra listener into it: same reasoning as that widget's own
/// doc just below — each wrapper here owns exactly one platform-
/// lifecycle concern, so `player_provider.dart` never needs to know how
/// Flutter delivers app-lifecycle events, only what to do once told the
/// app resumed. Wraps outside [_QuickActionsSync] (rather than inside)
/// so its `WidgetsBindingObserver` registration happens for the whole
/// app lifetime regardless of what either inner widget does.
class _AppLifecycleSync extends ConsumerStatefulWidget {
  final Widget child;

  const _AppLifecycleSync({required this.child});

  @override
  ConsumerState<_AppLifecycleSync> createState() => _AppLifecycleSyncState();
}

class _AppLifecycleSyncState extends ConsumerState<_AppLifecycleSync> with WidgetsBindingObserver {
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

/// Keeps the home-screen widget (Android App Widget / iOS WidgetKit —
/// see `android/.../NiceRadioWidgetProvider.kt` and
/// `ios/NiceRadioWidget/`) in sync with actual playback, in both
/// directions: pushes the station/song/play-state out to it whenever
/// they change, and relays taps on its own play/pause/skip buttons back
/// into [PlayerNotifier] — the exact same three actions the on-screen
/// buttons and the lock-screen notification already call.
///
/// WHY this lives here, wrapping the whole app, rather than inside
/// [PlayerNotifier]: same reasoning as [_QuickActionsSync] just below —
/// the player provider's job is playback, not how any particular
/// platform surface displays or controls it.
///
/// WHY the outbound push is de-duplicated by hand (three plain fields)
/// instead of `select`: the three values it cares about
/// (`currentStation?.id`, `nowPlayingTitle`, `isPlaying`) do not update
/// together as a single derived value the way, say, `stationsOfflineTrigger`
/// does — comparing each separately, once per `PlayerState` change, is
/// simpler here than composing a `select` tuple for three unrelated
/// fields.
class _HomeWidgetSync extends ConsumerStatefulWidget {
  final Widget child;

  const _HomeWidgetSync({required this.child});

  @override
  ConsumerState<_HomeWidgetSync> createState() => _HomeWidgetSyncState();
}

class _HomeWidgetSyncState extends ConsumerState<_HomeWidgetSync> {
  String? _lastStationId;
  String? _lastTitle;
  bool? _lastPlaying;

  // The station-logo box's bytes only ever depend on which station is
  // current (see StationArtworkService) — never on its title or play
  // state, which change far more often. Caching them here, keyed by
  // station id, means a title/play-state-only update just resends the
  // same already-resolved bytes instead of re-fetching or re-generating
  // artwork on every tick.
  String? _artworkStationId;
  Uint8List? _artworkBytes;

  // See _pushUpdate's own doc — bumped once per call, checked after the
  // one genuinely async step (the artwork fetch), to discard a call that
  // a newer one has since superseded.
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
    if (station.id == _lastStationId && title == _lastTitle && next.isPlaying == _lastPlaying) {
      return;
    }
    _lastStationId = station.id;
    _lastTitle = title;
    _lastPlaying = next.isPlaying;

    // Guards against a slower, earlier call finishing after a newer one —
    // e.g. switching stations quickly while a broken station's favicon
    // fetch (up to 5s, see StationArtworkService's own timeout) is still
    // in flight — and overwriting the widget with stale station/title
    // data for a station that is no longer current. Each call captures
    // its own generation number before the only `await` below; if a
    // later call already bumped it by the time this one comes back, this
    // one's result is discarded instead of pushed. Same shape as
    // RadioAudioHandler._rebuildMediaItem's own staleness guard, for the
    // same underlying race.
    final generation = ++_updateGeneration;

    if (station.id != _artworkStationId) {
      // Resolved once per station and reused after that — see this
      // state's own field doc just above.
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
    ref.listen<PlayerState>(playerProvider, (previous, next) {
      unawaited(_pushUpdate(next));
    });

    return widget.child;
  }
}

/// Wires the home-screen "Tocar rádio atual" shortcut to the player:
/// registers what happens when it is tapped, and keeps the shortcut's
/// label in sync with whatever station is actually current.
///
/// WHY this lives here, wrapping the whole app, rather than inside
/// [PlayerNotifier]: the player provider's job is playback, not the
/// home-screen icon — keeping this concern in the widget tree (where
/// `quick_actions` naturally belongs, since it is a platform/UI
/// integration) means `player_provider.dart` never needs to know
/// `QuickActionsService` exists. Cold-starting the app from the
/// shortcut still works too.
class _QuickActionsSync extends ConsumerStatefulWidget {
  final Widget child;

  const _QuickActionsSync({required this.child});

  @override
  ConsumerState<_QuickActionsSync> createState() => _QuickActionsSyncState();
}

class _QuickActionsSyncState extends ConsumerState<_QuickActionsSync> {
  String? _lastShortcutStationId;

  @override
  void initState() {
    super.initState();
    // Registers the tap handler once. `quick_actions` also delivers the
    // action that *launched* the app (a cold start from the shortcut)
    // through this same callback, so no separate cold-start check is
    // needed here.
    ref.read(quickActionsServiceProvider).initialize(
          () => ref.read(playerProvider.notifier).playFromQuickAction(),
        );
    // Same idea for Siri/Shortcuts (iOS) and launcher shortcuts / Google
    // Assistant (Android). Also delivers the command that launched the app.
    ref.read(voiceCommandServiceProvider).initialize(
          (command) => ref.read(voiceCommandHandlerProvider).handle(command),
        );
  }

  @override
  Widget build(BuildContext context) {
    // Compares by id (not object identity — RadioStation does not
    // override `==`) so the shortcut is only re-registered with the
    // platform when the station actually changes, not on every unrelated
    // player-state update (volume, play/pause, ...).
    // Keeps Siri/Shortcuts' list of station names in step with the state's
    // stations (iOS only; a no-op elsewhere).
    ref.listen<AsyncValue<List<RadioStation>>>(stationsProvider, (previous, next) {
      final stations = next.value;
      if (stations != null && stations.isNotEmpty) {
        final stateName = ref.read(settingsProvider).value?.selectedState;
        final abbreviation = BrazilianStates.all.where((uf) => uf.name == stateName).firstOrNull?.abbreviation;
        ref.read(voiceCommandServiceProvider).cacheStations(stations, stateAbbreviation: abbreviation);
      }
    });

    ref.listen<PlayerState>(playerProvider, (previous, next) {
      final stationId = next.currentStation?.id;
      if (stationId == _lastShortcutStationId) return;
      _lastShortcutStationId = stationId;
      ref.read(quickActionsServiceProvider).updateShortcut(next.currentStation);
    });

    return widget.child;
  }
}

/// Decides whether to show onboarding (first launch) or the home screen
/// (every launch after) — and keeps deciding for the rest of the
/// session, reacting to [onboardingDoneProvider] rather than handing off
/// to a one-time `Navigator` push.
///
/// WHY this matters, found by hand while chasing an unrelated bug (the
/// home-screen widget's data never updating): `OnboardingScreen` used to
/// finish by calling `Navigator.of(context).pushReplacement(...)` to a
/// bare `HomeScreen()`. That *replaces the current route* — and
/// `_AppLifecycleSync`/`_HomeWidgetSync`/`_QuickActionsSync` all sit
/// *above* this widget, inside that same original route (see
/// `NiceRadioApp.build`'s `home:`). Pushing a new route out from
/// underneath them didn't just swap the screen — it discarded their
/// entire State objects, and with them every `ref.listen` callback and
/// `WidgetsBindingObserver` registration those three widgets had set up,
/// replacing them with a `HomeScreen()` that had no wrappers around it
/// at all. Confirmed by hand: this app's home-screen widget, its
/// iOS-resume audio-session fix, and its home-screen quick-action
/// shortcut label all silently stopped updating the instant onboarding
/// finished — and all three worked again on the *next* cold start, since
/// a returning user skips `OnboardingScreen` entirely and this widget
/// builds `HomeScreen()` directly, inside the app's one and only route,
/// properly wrapped the whole time. Watching [onboardingDoneProvider]
/// here instead keeps the swap a plain widget rebuild inside that same
/// route, so nothing above it is ever torn down.
class _StartupGate extends ConsumerWidget {
  const _StartupGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onboardingDone = ref.watch(onboardingDoneProvider);
    return onboardingDone.when(
      data: (done) => done ? const HomeScreen() : const OnboardingScreen(),
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      // Falls back to onboarding rather than assuming it's done: showing
      // the prompt again (it has its own skip button) is the safe
      // default when the stored flag couldn't be read, not silently
      // treating an unknown state as "already done".
      error: (_, _) => const OnboardingScreen(),
    );
  }
}
