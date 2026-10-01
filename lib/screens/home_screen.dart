// The app's only "everyday" screen: current station, now playing, play
// controls, volume, favorite/sleep timer, and links to the station list
// and settings. Every other screen is reached from here.
//
// WHY a couple of pieces of state live in this widget (not in a
// provider): `_sleepPanelOpen` (is the sleep-timer picker expanded) and
// `_justCopied` (the brief checkmark after copying the song title) are
// purely cosmetic, screen-local, and never need to survive navigating
// away. Promoting them to global provider state would make the player
// provider bigger for no benefit — see player_provider.dart's own note
// on the same tradeoff for why favorite status went the other way.
//
// WHY the content blocks below (the station card, playback controls,
// volume, etc.) are separate widgets in `lib/widgets/` instead of private
// classes in this file: this file used to be over 1000 lines with 17
// classes in it — every one of those blocks is a self-contained,
// prop-driven widget with no reason to be hidden from the rest of the
// app, the same way `StationAvatar`/`ChoicePill`/`SegmentedToggle`
// already were. Splitting them out means "I want to change the volume
// card" points straight at `widgets/volume_card.dart`, not "somewhere in
// this 1000-line file". Only `HomeScreen`/`_HomeScreenState`/`_HomeContent`
// stay here — they are the actual *screen*: the piece that reads
// providers and wires callbacks, not a reusable widget on its own.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/radio_station.dart';
import '../providers/favorites_provider.dart';
import '../providers/player_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/stations_provider.dart';
import '../services/analytics_service.dart';
import '../theme/app_theme.dart';
import '../widgets/action_buttons_row.dart';
import '../widgets/choose_station_button.dart';
import '../widgets/empty_station_card.dart';
import '../widgets/error_banner.dart';
import '../widgets/lamp_icon.dart';
import '../widgets/no_state_selected.dart';
import '../widgets/playback_controls.dart';
import '../widgets/round_button.dart';
import '../widgets/segmented_toggle.dart';
import '../widgets/sleep_panel.dart';
import '../widgets/station_card.dart';
import '../widgets/stations_offline_dialog.dart';
import '../widgets/volume_card.dart';
import 'settings_screen.dart';
import 'station_list_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _sleepPanelOpen = false;
  bool _justCopied = false;
  Timer? _copyFeedbackTimer;

  @override
  void initState() {
    super.initState();
    // HomeScreen is never a pushed route (see `_StartupGate` in
    // main.dart — it's a conditional rebuild of `home:` itself), so the
    // `FirebaseAnalyticsObserver` attached to `MaterialApp` never sees it
    // the way it sees StationListScreen/SettingsScreen. Logged by hand
    // here instead, once, the moment this screen actually becomes visible.
    ref.read(analyticsServiceProvider).logScreenView('home');
  }

  @override
  void dispose() {
    _copyFeedbackTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The very first time the station list for the user's state loads
    // successfully, pre-select (but do not play) its first entry — see
    // PlayerNotifier.setInitialStation for why this never plays audio on
    // its own.
    ref.listen<AsyncValue<List<RadioStation>>>(visibleStationsProvider, (previous, next) {
      final stations = next.value;
      if (stations != null && stations.isNotEmpty) {
        ref.read(playerProvider.notifier).setInitialStation(stations.first);
      }
    });

    // Bumped by PlayerNotifier every time 3 connection attempts fail in
    // a row — see PlayerState.stationsOfflineTrigger's own doc. `select`
    // means this only fires on that specific counter changing, not on
    // every unrelated player-state change (volume, playback position,
    // etc.). `previous == null` only happens before this listener has
    // seen a first value, which should never itself be a trigger.
    ref.listen<int>(playerProvider.select((state) => state.stationsOfflineTrigger), (previous, next) {
      if (previous == null) return;
      final suppressed = ref.read(settingsProvider).value?.suppressOfflineWarning ?? false;
      if (suppressed) return;
      StationsOfflineDialog.show(context).then((dontShowAgain) {
        if (!mounted || dontShowAgain == null) return;
        ref.read(settingsProvider.notifier).setSuppressOfflineWarning(dontShowAgain);
      });
    });

    final settingsAsync = ref.watch(settingsProvider);
    final selectedState = settingsAsync.value?.selectedState;

    return Scaffold(
      body: SafeArea(
        child: selectedState == null
            ? NoStateSelected(
                isLoading: settingsAsync.isLoading,
                onChooseState: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                ),
              )
            : _HomeContent(
                sleepPanelOpen: _sleepPanelOpen,
                justCopied: _justCopied,
                onToggleSleepPanel: () => setState(() => _sleepPanelOpen = !_sleepPanelOpen),
                onCloseSleepPanel: () => setState(() => _sleepPanelOpen = false),
                onCopy: _handleCopy,
              ),
      ),
    );
  }

  void _handleCopy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    _copyFeedbackTimer?.cancel();
    setState(() => _justCopied = true);
    _copyFeedbackTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _justCopied = false);
    });
  }
}

class _HomeContent extends ConsumerWidget {
  final bool sleepPanelOpen;
  final bool justCopied;
  final VoidCallback onToggleSleepPanel;
  final VoidCallback onCloseSleepPanel;
  final ValueChanged<String> onCopy;

  const _HomeContent({
    required this.sleepPanelOpen,
    required this.justCopied,
    required this.onToggleSleepPanel,
    required this.onCloseSleepPanel,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(playerProvider);
    final viewMode = ref.watch(viewModeProviderOrAll);
    final favoriteIds = ref.watch(favoritesProviderOrEmpty);
    final visibleStations = ref.watch(visibleStationsProvider);
    final settingsValue = ref.watch(settingsProvider).value;
    final selectedState = settingsValue?.selectedState;
    final darkModeEnabled = settingsValue?.darkModeEnabled ?? false;
    // Shared by both header icon buttons, by explicit request, so
    // Settings always visually matches whatever "modo noturno" currently
    // is — blue when off (light mode: the lamp is lit), neutral once
    // dark mode is on. The lamp's own *shape* (rays or not — see
    // LampIcon) is still what actually carries the on/off meaning;
    // this is only the accent color riding along on top of it, same
    // reasoning as LampIcon's own doc comment.
    final headerIconColor = darkModeEnabled ? AppColors.textPrimary : AppColors.primary;

    final station = player.currentStation;
    final isFavorite = station != null && favoriteIds.contains(station.id);
    // A station can keep playing while the person switches to a tab that
    // doesn't include it — most commonly: playing an unfavorited station
    // from "Todas", then tapping "Favoritas" while nothing is favorited
    // yet. The station name/info card below reflects *this tab's*
    // content, not whatever happens to be playing in the background, so
    // "Favoritas" with nothing favorited shows the real "nenhuma estação
    // favoritada" message instead of confusingly displaying the name of
    // a station that isn't even in the list being shown. Playback itself
    // (the controls, volume, favorite star, etc. further down) is
    // deliberately left alone — someone should still be able to pause or
    // favorite whatever is actually playing from here.
    final showStationCard = station != null && (viewMode == StationViewMode.all || isFavorite);
    // Drives PlaybackControls' refresh mode — see its own `isRefreshMode`
    // doc. Mirrors EmptyStationCard's own "Todas empty, not Favoritas
    // empty" and "genuine fetch error, either tab" branches exactly, so
    // the button only takes over when that card is actually showing the
    // matching "toque para tentar novamente" text.
    final stationsUnavailable = visibleStations.hasError ||
        (visibleStations.hasValue && visibleStations.value!.isEmpty && viewMode != StationViewMode.favorites);

    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 10, 22, 18),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                // The app's actual launcher icon, not a generic Material
                // icon — so the header's own "logo" matches what the
                // person sees on their home screen, instead of two
                // different pictures both claiming to represent the app.
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset('assets/icon/icon.png', width: 28, height: 28),
                ),
                const SizedBox(width: 8),
                const Text('Nice Radio', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ],
            ),
            Row(
              children: [
                // A lamp, not a sun/moon pair: the icon's *shape* (a lit
                // bulb with rays vs. the same bulb with no rays) carries
                // the primary meaning, so this still isn't relying on
                // color as the *only* signal for state (see AppColors's
                // own class doc) even though, by explicit request, "on"
                // now also gets the app's default blue — a color accent
                // on top of an already-unambiguous shape change, not a
                // replacement for it. See LampIcon for why the rays are
                // drawn by hand instead of switching between two
                // different Material icons.
                RoundButton(
                  iconWidget: LampIcon(lit: !darkModeEnabled, color: headerIconColor),
                  tooltip: darkModeEnabled ? 'Ativar modo claro' : 'Ativar modo noturno',
                  iconSize: 22,
                  padding: const EdgeInsets.all(12),
                  onTap: () {
                    ref.read(analyticsServiceProvider).logButtonTap('night_mode_toggle');
                    ref.read(settingsProvider.notifier).toggleDarkMode();
                  },
                ),
                const SizedBox(width: 10),
                RoundButton(
                  icon: Icons.settings,
                  color: headerIconColor,
                  tooltip: 'Configurações',
                  iconSize: 22,
                  padding: const EdgeInsets.all(12),
                  onTap: () {
                    ref.read(analyticsServiceProvider).logButtonTap('settings_open');
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
                  },
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        SegmentedToggle(
          leftLabel: 'Favoritas',
          rightLabel: 'Todas',
          isLeftSelected: viewMode == StationViewMode.favorites,
          onSelectLeft: () => ref.read(viewModeProvider.notifier).showFavorites(),
          onSelectRight: () => ref.read(viewModeProvider.notifier).showAll(),
        ),
        const SizedBox(height: 12),
        if (!showStationCard)
          EmptyStationCard(visibleStations: visibleStations, viewMode: viewMode)
        else
          StationCard(
            station: station,
            nowPlaying: player.nowPlayingTitle,
            justCopied: justCopied,
            onCopy: () => onCopy(player.nowPlayingTitle ?? ''),
          ),
        const SizedBox(height: 12),
        PlaybackControls(
          isPlaying: player.isPlaying,
          isLoading: stationsUnavailable ? visibleStations.isLoading : player.isLoading,
          hasStation: station != null,
          isRefreshMode: stationsUnavailable,
          onPrevious: () {
            ref.read(analyticsServiceProvider).logButtonTap('previous_station');
            ref.read(playerProvider.notifier).playPrevious();
          },
          onTogglePlay: () {
            ref.read(analyticsServiceProvider).logButtonTap('play_pause');
            ref.read(playerProvider.notifier).togglePlayPause();
          },
          onNext: () {
            ref.read(analyticsServiceProvider).logButtonTap('next_station');
            ref.read(playerProvider.notifier).playNext();
          },
          onRefresh: () {
            ref.read(analyticsServiceProvider).logButtonTap('refresh_stations');
            ref.invalidate(stationsProvider);
          },
        ),
        // `player.errorMessage` is set whenever a stream fails to connect
        // (including the connection timing out — see PlayerNotifier's
        // `_connectTimeout`). Showing it here, right under the controls
        // that just failed, is more useful than a toast that can be
        // missed and disappears on its own.
        if (player.errorMessage != null) ...[
          const SizedBox(height: 12),
          ErrorBanner(message: player.errorMessage!),
        ],
        const SizedBox(height: 12),
        VolumeCard(volumePercent: player.volumePercent),
        const SizedBox(height: 12),
        ActionButtonsRow(
          isFavorite: isFavorite,
          sleepMinutes: player.sleepMinutes,
          sleepPanelOpen: sleepPanelOpen,
          hasStation: station != null,
          onToggleFavorite: station == null
              ? null
              : () {
                  ref.read(analyticsServiceProvider).logButtonTap('favorite_toggle');
                  ref.read(favoritesProvider.notifier).toggle(station.id);
                },
          onToggleSleepPanel: () {
            ref.read(analyticsServiceProvider).logButtonTap('sleep_panel_toggle');
            onToggleSleepPanel();
          },
        ),
        if (sleepPanelOpen) ...[
          const SizedBox(height: 12),
          SleepPanel(
            selectedMinutes: player.sleepMinutes,
            onSelect: (minutes) {
              ref.read(analyticsServiceProvider).logButtonTap('sleep_option');
              ref.read(playerProvider.notifier).setSleepMinutes(minutes);
              onCloseSleepPanel();
            },
          ),
        ],
        const SizedBox(height: 12),
        ChooseStationButton(
          onTap: () {
            ref.read(analyticsServiceProvider).logButtonTap('choose_station_open');
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const StationListScreen()));
          },
        ),
        const SizedBox(height: 12),
        Center(
          child: visibleStations.when(
            data: (list) => Text(
              viewMode == StationViewMode.favorites
                  ? 'Foram encontradas ${list.length} Rádios favoritas'
                  : (selectedState != null && selectedState.isNotEmpty)
                      ? 'Foram encontradas ${list.length} Rádios para $selectedState'
                      : 'Foram encontradas ${list.length} Rádios',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
            loading: () => Text('Buscando rádios...', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
            error: (_, _) => Text(
              'Não foi possível buscar as rádios. Verifique sua internet.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
          ),
        ),
      ],
    );
  }
}
