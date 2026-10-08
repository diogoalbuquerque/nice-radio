// Owns the single `just_audio` player and everything about "what is playing
// right now": play/pause, volume, next/previous, sleep timer, "now playing"
// title, data-usage estimate and listening-time analytics.
//
// One Notifier owns all of it because every action goes through the same
// `AudioPlayer` and they interact (switching station resets the title; the
// sleep timer must use the same pause path as the button). Platform pieces
// live in services: `AudioRoutingService` (session/speaker),
// `AudioInterruptionPauser` (WhatsApp-style interruptions), `ListeningTracker`.
import 'dart:async';
import 'dart:io' show Platform;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart' hide PlayerState;
import 'package:just_audio/just_audio.dart' as ja show PlayerState;

import '../models/radio_station.dart';
import '../services/analytics_service.dart';
import '../services/audio_interruption_pauser.dart';
import '../services/audio_player_handler.dart';
import '../services/audio_routing_service.dart';
import '../services/listening_tracker.dart';
import '../services/system_volume_service.dart';
import 'player_state.dart';
import 'settings_provider.dart';
import '../utils/station_lists.dart';
import 'stations_provider.dart';

export 'player_state.dart';

/// Lets tests substitute a fake without touching the real platform volume.
final systemVolumeServiceProvider = Provider<SystemVolumeService>((ref) {
  return SystemVolumeService();
});

/// Result of one connection attempt (`_attemptConnect`).
enum _ConnectOutcome { success, failed, superseded }

class PlayerNotifier extends Notifier<PlayerState> {
  // Live streams arrive at real-time pace, so no setting can build more than
  // seconds of forward buffer; this is a fixed cushion for network jitter
  // (constructor-only in `just_audio`). A user-facing buffer setting was
  // removed because its "2/5/10 min" labels promised the impossible.
  static const _forwardBufferDuration = Duration(seconds: 30);

  // 20s, not shorter: on iOS `setUrl()` for a healthy live stream can take
  // 8-10s. A timeout only stops *waiting* (native work continues), so a late
  // success is recovered by the listeners below instead of staying behind an
  // error. On web `just_audio`'s `play()` can hang, hence a timeout on every
  // `setUrl`/`play`.
  static const _connectTimeout = Duration(seconds: 20);

  // A failed attempt (fresh connect or mid-playback drop) retries the same
  // URL every 5s for 60s before showing an error: most failures are network
  // blips, not dead stations.
  static const _reconnectRetryWindow = Duration(seconds: 60);
  static const _reconnectRetryDelay = Duration(seconds: 5);

  // Every 3rd consecutive failure raises `stationsOfflineTrigger` (the dialog).
  static const _failuresBeforeOfflineDialog = 3;

  static const _usageTick = Duration(seconds: 5);

  late AudioPlayer _player;
  late SystemVolumeService _volumeService;
  late AudioInterruptionPauser _interruptionPauser;
  late ListeningTracker _listeningTracker;
  final _routing = const AudioRoutingService();
  RadioAudioHandler? _audioHandler;

  StreamSubscription<IcyMetadata?>? _icySubscription;
  StreamSubscription<ja.PlayerState>? _playerStateSubscription;
  StreamSubscription<PlayerException>? _errorSubscription;
  Timer? _sleepTimer; // fires the pause at the exact moment
  Timer? _sleepCountdownTimer; // refreshes the minutes shown on the button
  Timer? _dataUsageTimer;

  /// Which station's stream is loaded into [_player]: tells "pre-selected,
  /// never loaded" (see [setInitialStation]) apart from "loaded, just paused".
  String? _loadedStationId;

  /// Generation counter, bumped by every attempt to reach "playing"
  /// ([playStation], the resume branch, [_reconnectAfterDrop]). Results are
  /// written to `state` only if the attempt's token is still current: a slow
  /// failure from the old station must not overwrite the new station's
  /// success. Same pattern as `_HomeWidgetSyncState._updateGeneration` and
  /// `RadioAudioHandler._rebuildMediaItem` — use it for any new async write-back.
  int _loadToken = 0;

  int _consecutiveFailures = 0;
  bool _resolvingInitialStation = false;

  /// Latest station list, cached because `AudioService.init()` and the first
  /// station fetch race; whichever finishes first leaves it for the other.
  List<RadioStation>? _latestStations;

  /// The state the handler's browse list belongs to (fresh or cached); lets
  /// [nextBrowsableList] keep it when a refetch for that state comes back empty.
  String? _browsableForState;

  @override
  PlayerState build() {
    _player = _buildPlayer();
    _volumeService = ref.read(systemVolumeServiceProvider);
    _listeningTracker = ListeningTracker(
      (station, seconds) => ref.read(analyticsServiceProvider).logListeningSession(station, seconds),
    );
    _interruptionPauser = AudioInterruptionPauser(_player)..start();

    _attachIcyMetadataListener();
    _attachPlayerStateListener();
    _attachErrorListener();
    _startUsageTicker();
    _routing.configureSession(forceSpeaker: false);
    _initAudioService();
    _syncInitialSystemVolume();

    // Also covers the phone's hardware volume buttons.
    _volumeService.listen((percent) => state = state.copyWith(volumePercent: percent));

    // Feeds Android Auto's browse list (first list and every state change).
    // Also saved to disk, so the next cold start has a list before the fetch.
    ref.listen<AsyncValue<List<RadioStation>>>(stationsProvider, (previous, next) {
      final stations = next.value;
      // Skip refreshes: `value` is still the previous state's list while a new
      // state is loading, and must not be saved under the new state's name.
      if (stations == null || next.isLoading) return;
      final selectedState = ref.read(settingsProvider).value?.selectedState;
      final update = nextBrowsableList(
        fresh: stations,
        freshState: selectedState,
        currentListState: _browsableForState,
      );
      if (update == null) return;
      _latestStations = update;
      _browsableForState = selectedState;
      _audioHandler?.updateBrowsableStations(update);
      if (selectedState != null && update.isNotEmpty) {
        ref.read(storageServiceProvider).setBrowsableStations(selectedState, update);
      }
    }, fireImmediately: true);

    ref.onDispose(() {
      _icySubscription?.cancel();
      _playerStateSubscription?.cancel();
      _errorSubscription?.cancel();
      _interruptionPauser.dispose();
      _sleepTimer?.cancel();
      _sleepCountdownTimer?.cancel();
      _dataUsageTimer?.cancel();
      _volumeService.dispose();
      _player.dispose();
    });

    return const PlayerState.initial();
  }

  // ---------------------------------------------------------------- setup

  /// `androidApplyAudioAttributes: false`: see `AudioRoutingService
  /// .applyAndroidAudioAttributes` — it is applied explicitly before `setUrl`.
  AudioPlayer _buildPlayer() {
    return AudioPlayer(
      androidApplyAudioAttributes: false,
      audioLoadConfiguration: AudioLoadConfiguration(
        androidLoadControl: AndroidLoadControl(
          minBufferDuration: _forwardBufferDuration,
          maxBufferDuration: _forwardBufferDuration,
          bufferForPlaybackDuration: const Duration(seconds: 2),
          bufferForPlaybackAfterRebufferDuration: const Duration(seconds: 4),
        ),
        darwinLoadControl: DarwinLoadControl(preferredForwardBufferDuration: _forwardBufferDuration),
      ),
    );
  }

  /// Registers the `audio_service` handler (background playback, lock screen,
  /// Android Auto). Fire-and-forget because `build()` is synchronous; a
  /// failure only loses the lock-screen controls (iOS background audio comes
  /// from `UIBackgroundModes`).
  Future<void> _initAudioService() async {
    try {
      _audioHandler = await AudioService.init(
        builder: () => RadioAudioHandler(_player),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.nice.radio.channel.audio',
          androidNotificationChannelName: 'Nice Radio',
          // Keeps the foreground service across a pause; restarting one from
          // the background is restricted on Android 12+.
          androidStopForegroundOnPause: false,
        ),
      );
      final station = state.currentStation;
      if (station != null) _audioHandler!.setMediaItemForStation(station);
      _audioHandler!.onPlayStation = playStation;
      final latest = _latestStations;
      if (latest != null) _audioHandler!.updateBrowsableStations(latest);
      if (latest == null || latest.isEmpty) unawaited(_loadCachedBrowsableStations());
    } catch (_) {}
  }

  /// A car can bind the service seconds before the first station fetch ends
  /// (or with no network at all): give the handler the last saved list for the
  /// selected state meanwhile. A non-empty fresh list wins — it replaces this,
  /// or, if it landed while the cache was being read, stops this from applying.
  /// An *empty* [_latestStations] does not count as fresh: offline, the fetch
  /// fails within milliseconds and would otherwise block the cache.
  Future<void> _loadCachedBrowsableStations() async {
    try {
      final storage = ref.read(storageServiceProvider);
      final selectedState = await storage.getSelectedState();
      if (selectedState == null) return;
      final cached = await storage.getBrowsableStations(selectedState);
      if (cached == null || (_latestStations?.isNotEmpty ?? false)) return;
      _latestStations = cached;
      _browsableForState = selectedState;
      _audioHandler?.updateBrowsableStations(cached);
    } catch (_) {}
  }

  /// `build()` is synchronous, so the real system volume corrects the
  /// placeholder a moment later.
  Future<void> _syncInitialSystemVolume() async {
    final percent = await _volumeService.getVolumePercent();
    state = state.copyWith(volumePercent: percent);
  }

  // ------------------------------------------------------------ listeners

  /// Keeps `state.isPlaying` truthful no matter who changed the player (the
  /// button, the lock screen, the sleep timer).
  ///
  /// "Audio is really flowing" is `playing && processingState == ready`:
  /// `just_audio` sets `playing` the instant `play()` is *called* and carries
  /// it across `setUrl()` (it is intent, not output). Checking raw `playing`
  /// left the spinner stuck after switching from a playing station to a
  /// failing one. A genuine `readyToPlay` also wins over a stale error left
  /// by a timed-out attempt that later succeeded natively.
  void _attachPlayerStateListener() {
    _playerStateSubscription = _player.playerStateStream.listen((playerState) {
      final playing = playerState.playing;

      // Stopped from outside (notification Stop, OS reclaiming the player):
      // nothing is loaded, so the next Play must reconnect from scratch.
      if (playerState.processingState == ProcessingState.idle && _loadedStationId != null) {
        _loadedStationId = null;
      }

      final readyToPlay = playing && playerState.processingState == ProcessingState.ready;
      final needsUpdate =
          playing != state.isPlaying || (readyToPlay && (state.isLoading || state.errorMessage != null));
      if (!needsUpdate) return;

      if (readyToPlay) _consecutiveFailures = 0;
      state = state.copyWith(
        isPlaying: playing,
        isLoading: readyToPlay ? false : state.isLoading,
        errorMessage: readyToPlay ? null : state.errorMessage,
      );
    });
  }

  /// A mid-playback error (network dropped) arrives only on `errorStream`.
  /// Skipped while a connect is in flight (`isLoading`, handled by that
  /// attempt) or when not playing; deliberate pauses never raise one.
  void _attachErrorListener() {
    _errorSubscription = _player.errorStream.listen((_) {
      if (state.isLoading || !state.isPlaying) return;
      _reconnectAfterDrop();
    });
  }

  /// "Now playing" is best-effort ICY metadata; a real title is also a second,
  /// independent late-success signal (see [_attachPlayerStateListener]).
  void _attachIcyMetadataListener() {
    _icySubscription = _player.icyMetadataStream.listen((metadata) {
      final title = metadata?.info?.title?.trim();
      final hasTitle = title != null && title.isNotEmpty;
      if (hasTitle) _consecutiveFailures = 0;
      state = state.copyWith(
        isPlaying: hasTitle ? true : state.isPlaying,
        isLoading: hasTitle ? false : state.isLoading,
        nowPlayingTitle: hasTitle ? title : null,
        errorMessage: hasTitle ? null : state.errorMessage,
      );
      _audioHandler?.updateNowPlayingTitle(title);
    });
  }

  /// Data usage is an estimate (`bitrate × seconds played`, within a few
  /// percent for CBR streams); exact counts would need a local proxy. The
  /// same tick feeds the listening-time analytics.
  void _startUsageTicker() {
    _dataUsageTimer = Timer.periodic(_usageTick, (_) {
      final station = state.currentStation;
      final playing = state.isPlaying ? station : null;
      _listeningTracker.tick(playing, _usageTick.inSeconds);

      if (playing == null || playing.bitrateKbps <= 0) return;
      final bytesPerSecond = (playing.bitrateKbps * 1000) / 8;
      ref.read(settingsProvider.notifier).addDataUsage((bytesPerSecond * _usageTick.inSeconds).round());
    });
  }

  // ------------------------------------------------------------- playback

  /// Pre-selects a station without loading audio, so the home screen has
  /// something to show. Re-run whenever the visible list changes. Restores the
  /// last station by id from the *full* list (so the Favoritas tab cannot hide
  /// it), else falls back to the first one. Once something was actually
  /// loaded it is never swapped out.
  Future<void> setInitialStation(List<RadioStation> visibleStations) async {
    if (state.currentStation != null || _resolvingInitialStation) return;
    _resolvingInitialStation = true;
    try {
      final saved = await ref.read(storageServiceProvider).getLastStation();
      final pool = ref.read(stationsProvider).value ?? visibleStations;
      final station = pickInitialStation(pool, saved) ?? pickInitialStation(visibleStations, saved);
      // Re-checked after the await: a quick action/widget may have started one.
      if (station == null || state.currentStation != null) return;
      state = state.copyWith(currentStation: station);
      _persistLastStation(station);
    } finally {
      _resolvingInitialStation = false;
    }
  }

  /// The single choke point for starting a station (list, next/previous,
  /// quick action, Android Auto, widget, lock-screen skip), so analytics and
  /// retry live here once.
  Future<void> playStation(RadioStation station) async {
    final token = ++_loadToken;
    state = state.copyWith(
      currentStation: station,
      isLoading: true,
      nowPlayingTitle: null, // the old song title no longer applies
      errorMessage: null,
    );
    _persistLastStation(station);
    _audioHandler?.setMediaItemForStation(station);
    ref.read(analyticsServiceProvider).logStationPlayed(station);
    await _updateSpeakerForConnectedDevices();
    await _connectWithRetry(station, token: token);
  }

  void _persistLastStation(RadioStation station) {
    ref.read(storageServiceProvider).setLastStation(station);
  }

  /// "Tocar rádio atual" shortcut: the current station, or (cold start, no
  /// in-memory state) the last persisted one.
  Future<void> playFromQuickAction() async {
    final station = state.currentStation ?? await ref.read(storageServiceProvider).getLastStation();
    if (station == null) return;
    await playStation(station);
  }

  Future<void> togglePlayPause() async {
    final station = state.currentStation;
    if (station == null) return;

    // Only pre-selected (see setInitialStation): nothing loaded yet.
    if (_loadedStationId != station.id) {
      await playStation(station);
      return;
    }

    if (state.isPlaying) {
      await _player.pause(); // no network round-trip, so no timeout/spinner
      state = state.copyWith(isPlaying: false);
      return;
    }

    // Resuming still talks to the network (live radio has no local buffer),
    // so it gets the spinner, the timeout and its own token.
    final token = ++_loadToken;
    state = state.copyWith(isLoading: true);
    await _updateSpeakerForConnectedDevices();
    try {
      await _player.play().timeout(_connectTimeout);
      if (token != _loadToken) return; // superseded by a station switch
      _consecutiveFailures = 0;
      // The title is cleared on resume: live radio has no paused position, so
      // the old song is almost certainly not airing anymore.
      // `_attachIcyMetadataListener` refills it. The notification caches its
      // own title, hence the second call.
      state = state.copyWith(
        isPlaying: true,
        isLoading: _player.processingState != ProcessingState.ready,
        nowPlayingTitle: null,
        errorMessage: null,
      );
      _audioHandler?.updateNowPlayingTitle(null);
    } catch (_) {
      _setPlaybackError(token);
    }
  }

  Future<void> playNext() => _shiftStation(1);
  Future<void> playPrevious() => _shiftStation(-1);

  /// Moves within the currently visible list (respects Favoritas/Todas).
  Future<void> _shiftStation(int delta) async {
    final stations = ref.read(visibleStationsProvider).value;
    if (stations == null || stations.isEmpty) return;

    final currentId = state.currentStation?.id;
    final currentIndex = currentId == null ? -1 : stations.indexWhere((s) => s.id == currentId);
    final index = (currentIndex + delta) % stations.length; // Dart's % is never negative
    await playStation(stations[index]);
  }

  // ------------------------------------------------- connect / reconnect

  /// One attempt to load and play [station]. Never touches the error fields:
  /// that is `_connectWithRetry`'s job once *all* retries are exhausted, so a
  /// retry loop does not flash an error between attempts.
  Future<_ConnectOutcome> _attemptConnect(RadioStation station, {required int token}) async {
    try {
      await _routing.applyAndroidAudioAttributes(_player);
      await _player.setUrl(station.streamUrl).timeout(_connectTimeout);
      if (token != _loadToken) return _ConnectOutcome.superseded;
      _loadedStationId = station.id;
      _consecutiveFailures = 0;
      await _player.play().timeout(_connectTimeout);
      if (token != _loadToken) return _ConnectOutcome.superseded;
      // `play()` resolves when playback is *requested*, not when audio flows,
      // so the spinner stays until `processingState` is ready (or the state
      // listener confirms it). `errorMessage: null` clears a banner left by an
      // earlier failed attempt at this station.
      state = state.copyWith(
        isPlaying: true,
        isLoading: _player.processingState != ProcessingState.ready,
        errorMessage: null,
      );
      return _ConnectOutcome.success;
    } catch (_) {
      return token == _loadToken ? _ConnectOutcome.failed : _ConnectOutcome.superseded;
    }
  }

  /// Attempts to connect and keeps quietly retrying (spinner up, no error)
  /// until [_reconnectRetryWindow] elapses, then reports the error once.
  /// Per-attempt errors would trip the 3-failure dialog after 15s.
  Future<void> _connectWithRetry(RadioStation station, {required int token}) async {
    final deadline = DateTime.now().add(_reconnectRetryWindow);
    while (true) {
      if (token != _loadToken) return;
      final outcome = await _attemptConnect(station, token: token);
      if (outcome != _ConnectOutcome.failed) return; // success, or superseded
      if (!DateTime.now().isBefore(deadline)) break;
      await Future.delayed(_reconnectRetryDelay);
    }
    _setPlaybackError(token);
  }

  /// Retries the same station after an unexpected mid-playback drop. The title
  /// is cleared for the same reason as on resume.
  Future<void> _reconnectAfterDrop() async {
    final station = state.currentStation;
    if (station == null) return;

    final token = ++_loadToken;
    state = state.copyWith(isPlaying: false, isLoading: true, nowPlayingTitle: null, errorMessage: null);
    _audioHandler?.updateNowPlayingTitle(null);
    await _connectWithRetry(station, token: token);
  }

  /// Shared failure state. Bails out when the attempt is stale (`token`) or
  /// when audio is genuinely flowing — a timeout does not prove failure, and
  /// an error written over working audio would sit there forever. Every 3rd
  /// failure in a row also bumps `stationsOfflineTrigger` (the dialog is not
  /// meant to fire on every failure; the inline `ErrorBanner` covers one).
  void _setPlaybackError(int token) {
    if (token != _loadToken) return;
    if (_player.playing && _player.processingState == ProcessingState.ready) return;

    _consecutiveFailures++;
    final reachedLimit = _consecutiveFailures >= _failuresBeforeOfflineDialog;
    if (reachedLimit) _consecutiveFailures = 0;

    state = state.copyWith(
      isPlaying: false,
      isLoading: false,
      nowPlayingTitle: null,
      errorMessage: 'Rádio não disponível no momento. Tente outra estação.',
      stationsOfflineTrigger: reachedLimit ? state.stationsOfflineTrigger + 1 : state.stationsOfflineTrigger,
    );
  }

  // -------------------------------------------------------------- routing

  /// Run at the start of every attempt to start audio (a device may be
  /// plugged in between plays): forces the phone speaker only when nothing
  /// external is connected. `PlayerState.speakerOn` starts false — forcing it
  /// at launch hijacked Bluetooth/car audio.
  Future<void> _updateSpeakerForConnectedDevices() async {
    final forceSpeaker = await _routing.shouldForceSpeaker();
    if (forceSpeaker == null || forceSpeaker == state.speakerOn) return;
    state = state.copyWith(speakerOn: forceSpeaker);
    await _routing.configureSession(forceSpeaker: forceSpeaker);
  }

  /// Called by `_AppLifecycleSync` on every `AppLifecycleState.resumed`.
  /// iOS-only and a no-op with no station loaded: iOS can drop the Now Playing
  /// status while audio keeps playing, so the session is re-asserted and the
  /// lock-screen info re-published. Android's foreground service + MediaSession
  /// has no equivalent loss.
  Future<void> handleAppResumed() async {
    if (kIsWeb || !Platform.isIOS) return;
    if (state.currentStation == null) return;
    await _routing.reactivateSession(forceSpeaker: state.speakerOn);
    _audioHandler?.refreshNowPlayingInfo();
  }

  // ------------------------------------------------------ volume & timers

  /// Moves the phone's *system* volume in 10% steps (fixed steps are easier to
  /// hit than a slider). The state update is optimistic; the system-volume
  /// listener confirms or corrects it.
  void setVolumePercent(int percent) {
    final clamped = percent.clamp(0, 100);
    state = state.copyWith(volumePercent: clamped);
    _volumeService.setVolumePercent(clamped);
  }

  void increaseVolume() => setVolumePercent(state.volumePercent + 10);
  void decreaseVolume() => setVolumePercent(state.volumePercent - 10);

  /// Clears a stale "Rádio não disponível" banner when the person picks another
  /// state. Only the text: it must never interrupt playback.
  void clearError() {
    if (state.errorMessage == null) return;
    state = state.copyWith(errorMessage: null);
  }

  /// Sets (or clears, with 0) the sleep timer, replacing any previous one.
  /// Timers live in memory only, so closing the app cancels the sleep timer.
  void setSleepMinutes(int minutes) {
    _sleepTimer?.cancel();
    _sleepCountdownTimer?.cancel();
    state = state.copyWith(sleepMinutes: minutes, sleepRemainingMinutes: minutes);
    if (minutes <= 0) return;

    final endsAt = DateTime.now().add(Duration(minutes: minutes));
    _sleepTimer = Timer(Duration(minutes: minutes), () async {
      _sleepCountdownTimer?.cancel();
      await _player.pause();
      state = state.copyWith(isPlaying: false, sleepMinutes: 0, sleepRemainingMinutes: 0);
    });
    // Only touches state when the displayed minute actually changes.
    _sleepCountdownTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      final remaining = remainingSleepMinutes(endsAt, DateTime.now());
      if (remaining > 0 && remaining != state.sleepRemainingMinutes) {
        state = state.copyWith(sleepRemainingMinutes: remaining);
      }
    });
  }
}

final playerProvider = NotifierProvider<PlayerNotifier, PlayerState>(
  PlayerNotifier.new,
);
