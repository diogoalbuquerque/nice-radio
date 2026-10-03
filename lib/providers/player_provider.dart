// Owns the single `just_audio` player instance and everything about "what
// is playing right now": play/pause, volume, next/previous station, the
// sleep timer, the "now playing" song title (when the stream provides
// it), and the rolling data-usage estimate.
//
// WHY one Notifier owns all of this instead of splitting it further:
// every one of these actions ultimately has to go through the same
// `AudioPlayer` instance, and several of them interact (e.g. changing
// station must reset "now playing"; the sleep timer must call the same
// pause path as the button does). Keeping them together avoids two
// different code paths for "pause the radio" that could drift apart.
//
// WHY favorite status is deliberately NOT stored here: it already lives
// in [favoritesProvider], keyed by station id. Duplicating an `isFavorite`
// flag into this state would create two sources of truth that could
// disagree (e.g. if a station is favorited from the station list while
// it is also the one currently playing). The UI reads both providers and
// combines them instead.
import 'dart:async';
import 'dart:io' show Platform;

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../models/radio_station.dart';
import '../services/analytics_service.dart';
import '../services/audio_player_handler.dart';
import '../services/system_volume_service.dart';
import 'settings_provider.dart';
import 'stations_provider.dart';

/// Shared instance of [SystemVolumeService]. WHY a provider for a plain
/// class with no state of its own: same reason as
/// `settings_provider.dart`'s `storageServiceProvider` — it lets tests
/// substitute a fake without touching the real platform volume APIs.
final systemVolumeServiceProvider = Provider<SystemVolumeService>((ref) {
  return SystemVolumeService();
});

/// Result of a single connection attempt in [PlayerNotifier]'s
/// `_attemptConnect`/`_connectWithRetry` pair — see their docs.
enum _ConnectOutcome { success, failed, superseded }

class PlayerState {
  final RadioStation? currentStation;
  final bool isPlaying;
  final bool isLoading;
  final int volumePercent; // 0-100, always a multiple of 10 (see setVolumePercent)
  final int sleepMinutes; // 0 means "no timer set"
  final bool speakerOn;
  final String? nowPlayingTitle;
  final String? errorMessage;
  // Bumped by PlayerNotifier every time 3 connection attempts fail in a
  // row (see _setPlaybackError) — the home screen watches this to know
  // when to show StationsOfflineDialog. A plain counter, not a bool,
  // because it needs to fire again on the *next* run of 3 failures even
  // if the dialog was already shown once — a bool flip back to the same
  // `true` value wouldn't be a new event for a ref.listen comparing
  // previous vs. next.
  final int stationsOfflineTrigger;

  const PlayerState({
    required this.currentStation,
    required this.isPlaying,
    required this.isLoading,
    required this.volumePercent,
    required this.sleepMinutes,
    required this.speakerOn,
    required this.nowPlayingTitle,
    required this.errorMessage,
    required this.stationsOfflineTrigger,
  });

  const PlayerState.initial()
      : currentStation = null,
        isPlaying = false,
        isLoading = false,
        volumePercent = 60,
        sleepMinutes = 0,
        // Starts OFF: the default is whatever the phone is already doing
        // (its own speaker, or a connected Bluetooth/wired device) — see
        // _configureAudioSession's WHY comment. This field is no longer a
        // user-facing toggle (see _updateSpeakerForConnectedDevices): it is
        // recomputed automatically at the start of every play attempt, from
        // whatever is connected at that moment — `false` here is just the
        // harmless value it holds before the very first such check ever
        // runs, not a meaningful "off by default" choice anymore.
        speakerOn = false,
        nowPlayingTitle = null,
        errorMessage = null,
        stationsOfflineTrigger = 0;

  // A private sentinel, distinct from every real value (including
  // `null` itself), used only as `copyWith`'s default for the two
  // nullable fields below — see the doc comment on `copyWith` for why
  // this exists at all.
  static const Object _unset = Object();

  /// Returns a copy of this state with the given fields replaced.
  ///
  /// `nowPlayingTitle` and `errorMessage` accept an explicit `null` to
  /// *clear* that field — e.g. `copyWith(errorMessage: null)` — which a
  /// plain `String? errorMessage` parameter could not do, since Dart's
  /// `??` has no way to tell "clear this" apart from "leave this alone"
  /// once both look like `null` to the parameter. `_unset` (a value no
  /// caller can ever produce by accident) is what stands for "leave
  /// alone" here instead, checked with `identical` rather than `==` so
  /// even a future value class with a custom `==` couldn't accidentally
  /// match it.
  ///
  /// This used to not exist for exactly these two fields (see this
  /// project's git history) — every call site in `PlayerNotifier` that
  /// needed to set or clear one of them had to reconstruct the entire
  /// 9-field `PlayerState` by hand instead, copying the other 7 fields
  /// across unchanged each time. That was seven near-identical
  /// 10+-line blocks doing the same job this one method now does once.
  PlayerState copyWith({
    RadioStation? currentStation,
    bool? isPlaying,
    bool? isLoading,
    int? volumePercent,
    int? sleepMinutes,
    bool? speakerOn,
    Object? nowPlayingTitle = _unset,
    Object? errorMessage = _unset,
    int? stationsOfflineTrigger,
  }) {
    return PlayerState(
      currentStation: currentStation ?? this.currentStation,
      isPlaying: isPlaying ?? this.isPlaying,
      isLoading: isLoading ?? this.isLoading,
      volumePercent: volumePercent ?? this.volumePercent,
      sleepMinutes: sleepMinutes ?? this.sleepMinutes,
      speakerOn: speakerOn ?? this.speakerOn,
      nowPlayingTitle:
          identical(nowPlayingTitle, _unset) ? this.nowPlayingTitle : nowPlayingTitle as String?,
      errorMessage: identical(errorMessage, _unset) ? this.errorMessage : errorMessage as String?,
      stationsOfflineTrigger: stationsOfflineTrigger ?? this.stationsOfflineTrigger,
    );
  }
}

class PlayerNotifier extends Notifier<PlayerState> {
  late AudioPlayer _player;
  late SystemVolumeService _volumeService;
  StreamSubscription<IcyMetadata?>? _icySubscription;
  // `dynamic` here (rather than the more precise `just_audio.PlayerState`)
  // is deliberate: this file already declares its own `PlayerState` class
  // above, and that local declaration shadows the identically-named type
  // just_audio exports — there is no way to write the import's version
  // unqualified in this file. The callback below never needs to name the
  // type explicitly, so `dynamic` avoids the collision entirely rather
  // than pulling in a second, prefixed import just for one type name.
  StreamSubscription<dynamic>? _playerStateSubscription;
  StreamSubscription<PlayerException>? _errorSubscription;
  StreamSubscription<AudioInterruptionEvent>? _duckInterruptionSubscription;
  Timer? _sleepTimer;
  Timer? _dataUsageTimer;
  RadioAudioHandler? _audioHandler;

  /// Set by [_attachDuckInterruptionListener] right before it pauses for a
  /// duck-type interruption, so the matching "interruption ended" event
  /// only resumes playback that *this* listener actually paused — the
  /// same "only resume what we interrupted" guard `just_audio`'s own
  /// built-in interruption handling uses for its `pause`-type events (see
  /// that listener's own doc for why a plain flag isn't enough on its
  /// own: someone pausing manually mid-interruption must not get resumed
  /// out from under them once the interruption ends).
  bool _duckPaused = false;

  /// Cached independently of [_audioHandler]'s own lifecycle — see the
  /// `ref.listen(stationsProvider, ...)` registration in [build] for why:
  /// `AudioService.init()` (which creates [_audioHandler]) and
  /// `stationsProvider`'s first network fetch are two separate async
  /// operations racing each other, and whichever finishes first needs
  /// somewhere to stash its result for the other to pick up once it also
  /// finishes.
  List<RadioStation>? _latestStations;

  @override
  PlayerState build() {
    _player = _buildPlayer();
    _attachIcyMetadataListener();
    _attachPlayerStateListener();
    _attachErrorListener();
    _attachDuckInterruptionListener();
    _startDataUsageTicker();
    _configureAudioSession();
    _initAudioService();

    _volumeService = ref.read(systemVolumeServiceProvider);
    _syncInitialSystemVolume();
    // Keeps the on-screen percentage in sync when the volume changes for
    // a reason other than this app's own +/- buttons — most notably the
    // phone's physical volume buttons. See SystemVolumeService's class
    // doc for why the in-app volume is the *system* volume at all.
    _volumeService.listen((percent) => state = state.copyWith(volumePercent: percent));

    // Keeps Android Auto's browse list (see RadioAudioHandler.getChildren)
    // in sync with whatever state the user has selected — both the very
    // first list (fireImmediately, racing AudioService.init() below — see
    // _latestStations' doc) and every later change, e.g. after picking a
    // different state in Settings.
    ref.listen<AsyncValue<List<RadioStation>>>(stationsProvider, (previous, next) {
      final stations = next.value;
      if (stations == null) return;
      _latestStations = stations;
      _audioHandler?.updateBrowsableStations(stations);
    }, fireImmediately: true);

    ref.onDispose(() {
      _icySubscription?.cancel();
      _playerStateSubscription?.cancel();
      _errorSubscription?.cancel();
      _duckInterruptionSubscription?.cancel();
      _sleepTimer?.cancel();
      _dataUsageTimer?.cancel();
      _volumeService.dispose();
      _player.dispose();
    });

    return const PlayerState.initial();
  }

  /// Registers this app's `AudioHandler` with `audio_service`, which is
  /// what makes the phone treat the radio as a real "now playing" media
  /// session — keeping playback alive in the background (not just muted
  /// or suspended) and surfacing play/pause/stop controls on the lock
  /// screen and notification shade, the same way any music or podcast app
  /// does. See `audio_player_handler.dart` for the handler itself.
  ///
  /// WHY this is fire-and-forget (not awaited before `build()` returns):
  /// `build()` must return a [PlayerState] synchronously, the same
  /// reasoning as [_syncInitialSystemVolume] below. Playback itself does
  /// not depend on this having finished — the app works exactly as
  /// before if the notification integration takes a moment to register,
  /// or (wrapped in try/catch) fails outright on a platform quirk.
  Future<void> _initAudioService() async {
    try {
      _audioHandler = await AudioService.init(
        builder: () => RadioAudioHandler(_player),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.nice.radio.channel.audio',
          androidNotificationChannelName: 'Nice Radio',
          // Keeps the Android foreground service (and thus playback)
          // alive across a pause instead of tearing it down — the
          // package's own docs recommend this to avoid a
          // ForegroundServiceStartNotAllowedException if the user later
          // resumes from the notification after the app has been in the
          // background for a while (Android 12+ restricts restarting a
          // foreground service from the background).
          androidStopForegroundOnPause: false,
        ),
      );
      final station = state.currentStation;
      if (station != null) _audioHandler!.setMediaItemForStation(station);
      _audioHandler!.onPlayStation = playStation;
      // Covers the ordering where the station list finished loading
      // *before* this handler existed to receive it — see _latestStations'
      // doc comment. If it arrives after instead, the ref.listen above
      // covers that ordering.
      if (_latestStations != null) _audioHandler!.updateBrowsableStations(_latestStations!);
    } catch (_) {
      // Best-effort: on iOS, background playback itself is already
      // covered by Info.plist's `UIBackgroundModes: audio` regardless of
      // this notification integration, so a failure here should never
      // stop the radio from playing — only make the lock-screen controls
      // unavailable.
    }
  }

  /// Keeps `state.isPlaying` truthful no matter *what* changed the
  /// player's actual playing state — this app's own Play button, the
  /// lock-screen/notification controls (via [RadioAudioHandler]), or the
  /// sleep timer pausing things directly. Before this listener existed,
  /// `state.isPlaying` was only ever set manually at each call site that
  /// happened to know about it, which is exactly the kind of thing that
  /// silently goes stale the moment a new way to pause/play is added —
  /// as background/lock-screen control now is.
  void _attachPlayerStateListener() {
    _playerStateSubscription = _player.playerStateStream.listen((playerState) {
      final playing = playerState.playing;

      // A stream stopped from outside this notifier (the notification's
      // Stop control, or the OS reclaiming the player) leaves nothing
      // loaded — the next Play must reconnect from scratch, not try to
      // resume a source that is no longer there.
      if (playerState.processingState == ProcessingState.idle && _loadedStationId != null) {
        _loadedStationId = null;
      }

      // WHY `readyToPlay` (playing AND processingState.ready), not just
      // `playing` alone, decides when the loading spinner clears: `just_audio`
      // sets its `playing` flag the instant `play()` is called — essentially
      // synchronously — regardless of whether the stream has actually
      // started delivering audio yet. Using `playing` alone here meant
      // switching stations (or resuming) showed the pause icon immediately,
      // *before* any real audio had connected — indistinguishable from
      // already playing, by direct report. `processingState == ready` is
      // `just_audio`'s own signal that buffering finished and audio is
      // genuinely about to come out of the speaker, which is what the
      // loading spinner is actually meant to cover.
      final readyToPlay = playing && playerState.processingState == ProcessingState.ready;

      // WHY this can't be a plain `copyWith(isPlaying: playing)`: on
      // iOS, `just_audio`'s `setUrl()` Future only resolves once AVFoundation
      // reports `AVPlayerItemStatusReadyToPlay` — which, for a live
      // stream, has no fixed upper bound and can occasionally take
      // longer than `_connectTimeout`. Dart's `Future.timeout()` does
      // *not* cancel the underlying call when that happens — it only
      // stops *waiting* for it — so the native side can and does keep
      // connecting in the background and genuinely start playing
      // *after* `_setPlaybackError()` already put an error on screen.
      // Confirmed by hand: `xcrun simctl ... log stream` showing
      // continuous audio buffers enqueueing at the exact moment the
      // "Não foi possível tocar" banner was visible. This listener is
      // the one place that hears about that late success directly from
      // the player, so it is the one place that can correct it — a
      // genuine `readyToPlay` here always wins over a stale
      // `isLoading`/`errorMessage`, regardless of which call site set
      // them or how out of date they've become.
      final needsUpdate =
          playing != state.isPlaying || (readyToPlay && (state.isLoading || state.errorMessage != null));
      if (needsUpdate) {
        if (readyToPlay) _resetFailureStreak();
        state = state.copyWith(
          isPlaying: playing,
          isLoading: readyToPlay ? false : state.isLoading,
          errorMessage: readyToPlay ? null : state.errorMessage,
        );
      }

    });
  }

  /// `just_audio` surfaces a genuine player error (a stream that dies
  /// mid-play — most commonly the network dropping — not just an initial
  /// connection failure) on `errorStream`, independently of whatever
  /// `playerStateStream` happens to be reporting. By default nothing in
  /// this app listened to it at all, so a real report matched this
  /// exactly: the radio simply reverted to a silent, non-playing state
  /// with no spinner and no error message the moment the network cut out
  /// mid-song — `_attachPlayerStateListener` alone has no way to tell
  /// "the connection just died" apart from "the person just paused", and
  /// without this listener nothing ever tried to reconnect on its own.
  ///
  /// WHY `state.isLoading || !state.isPlaying` skips it: an error during
  /// a *fresh* connection attempt (a station tap, next/previous, a
  /// resume) is already being handled by that attempt's own
  /// `_attemptConnect`/`togglePlayPause` timeout — `isLoading` is true
  /// for the whole time one of those is in flight, so this only ever
  /// reacts to an error that arrives while we were genuinely, already
  /// playing with nothing else going on. A *deliberate* stop
  /// (`togglePlayPause`'s pause branch, the sleep timer, a duck
  /// interruption) never raises a `PlayerException` in the first place —
  /// all three only ever call `_player.pause()` — so this never mistakes
  /// an intentional pause for a dropped connection.
  void _attachErrorListener() {
    _errorSubscription = _player.errorStream.listen((_) {
      if (state.isLoading || !state.isPlaying) return;
      _reconnectAfterDrop();
    });
  }

  /// Reacts to an unexpected mid-playback error (see
  /// [_attachErrorListener]) by immediately showing the same loading
  /// spinner a fresh connection attempt would, then handing off to
  /// [_connectWithRetry] to quietly retry the same station for a while
  /// before falling back to the ordinary error/play state — see that
  /// method's own doc. `nowPlayingTitle` is cleared for the same reason
  /// [togglePlayPause]'s resume branch clears it: this is live radio, so
  /// whatever was airing before the drop is not guaranteed to still be
  /// airing once reconnected, and `_attachIcyMetadataListener` will
  /// repopulate it from the reconnected stream's next ICY block anyway.
  Future<void> _reconnectAfterDrop() async {
    final station = state.currentStation;
    if (station == null) return;

    final token = ++_loadToken;
    state = state.copyWith(
      isPlaying: false,
      isLoading: true,
      nowPlayingTitle: null,
      errorMessage: null,
    );
    _audioHandler?.updateNowPlayingTitle(null);
    await _connectWithRetry(station, token: token);
  }

  /// Pauses (and later auto-resumes) playback for a "duck"-type audio
  /// interruption — another app briefly taking partial audio focus, e.g.
  /// WhatsApp playing back or recording a voice message. Reported
  /// directly: sending or listening to a WhatsApp audio while the radio
  /// was playing left the radio at full, unducked volume the whole time
  /// — unlike Spotify and similar apps, which duck or pause automatically.
  ///
  /// WHY this exists at all, instead of relying on `just_audio`'s own
  /// built-in interruption handling (`handleInterruptions`, on by default
  /// and left on here — this listener is a *supplement*, not a
  /// replacement, and never touches the `pause`/`unknown` cases below):
  /// confirmed by reading `just_audio 0.10.6`'s own source
  /// (`lib/just_audio.dart`), its built-in `AudioInterruptionType.duck`
  /// handler only ever lowers volume when the session's
  /// `androidAudioAttributes.usage == AndroidAudioUsage.game` — a narrow
  /// special case that does not apply to this app's `usage: media` (see
  /// `_applyAndroidAudioAttributes`), so for every other usage, including
  /// ours, a duck-type interruption is a silent no-op there. `pause`/
  /// `unknown`-type interruptions (a real phone call, another app taking
  /// full/exclusive focus) are genuinely handled correctly by that
  /// built-in logic already and are deliberately left alone here.
  ///
  /// A real volume *duck* (temporarily lowering the player's own gain)
  /// was considered and rejected: this app's player is always kept at
  /// full gain by design, with loudness controlled entirely through the
  /// phone's system volume (see `SystemVolumeService`'s own doc) — adding
  /// a second, hidden "ducked volume" would be exactly the kind of
  /// second volume concept that design deliberately avoids, and would
  /// risk leaving the player silently stuck at a lowered gain if an
  /// "interruption ended" event was ever missed. Pausing (and resuming
  /// only what this listener itself paused — the same
  /// pattern `just_audio`'s own `pause`-type handling already uses, via
  /// its own `_playInterrupted` flag) is simpler and has no such
  /// failure mode: a missed "ended" event just leaves the radio paused,
  /// exactly like any other pause, rather than quietly too quiet.
  void _attachDuckInterruptionListener() {
    AudioSession.instance.then((session) {
      _duckInterruptionSubscription = session.interruptionEventStream.listen((event) {
        if (event.type != AudioInterruptionType.duck) return;
        if (event.begin) {
          if (_player.playing) {
            _duckPaused = true;
            _player.pause();
          }
        } else if (_duckPaused) {
          _duckPaused = false;
          _player.play();
        }
      });
    });
  }

  /// `build()` must return synchronously, but reading the real system
  /// volume is async — so the constructor-time state starts with
  /// [PlayerState.initial]'s placeholder value and this corrects it a
  /// moment later, once the platform actually answers.
  Future<void> _syncInitialSystemVolume() async {
    final percent = await _volumeService.getVolumePercent();
    state = state.copyWith(volumePercent: percent);
  }

  /// How far ahead of the current playback position `just_audio` is told
  /// to buffer. Used to be a user-facing Settings choice (2/5/10
  /// minutes) — removed after a direct real-world test (turning off
  /// Wi-Fi mid-playback) showed the radio still stopped within seconds
  /// no matter which of the three was picked. The reason: these are
  /// *live* Icecast/Shoutcast streams, not files — the server sends
  /// audio at roughly real-time pace as it is broadcast, so there is no
  /// "next 10 minutes" sitting on the server for the client to download
  /// ahead of time. In practice the player can never accumulate more
  /// than a handful of seconds of true forward buffer, regardless of how
  /// high `maxBufferDuration` is set — so exposing 2/5/10-minute choices
  /// was promising something this kind of stream can never deliver. This
  /// fixed value is just a sensible, modest cushion for ordinary network
  /// jitter/brief drops — the only thing forward-buffering a live stream
  /// can ever actually help with.
  static const _forwardBufferDuration = Duration(seconds: 30);

  /// WHY `androidApplyAudioAttributes: false`: by default, `just_audio`
  /// reacts to `audio_session`'s configuration (see
  /// `_configureAudioSession`) by subscribing to its
  /// `configurationStream` and calling `AudioPlayer.setAndroidAudioAttributes`
  /// on its own schedule, entirely outside this app's control. That call
  /// starts its own async "platform activation" on this same player —
  /// and `just_audio` tracks activations with one shared counter, so if
  /// it overlaps with this app's own `setUrl()` (see
  /// `_applyAndroidAudioAttributes`'s WHY comment for the reproduction),
  /// whichever activation started first is silently cancelled
  /// (`PlayerInterruptedException: Loading interrupted`) — sometimes
  /// taking the load itself down with it. Turning this off does not lose
  /// the feature: `_applyAndroidAudioAttributes` below sets the same
  /// attributes explicitly, awaited, under this app's own control.
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
        darwinLoadControl: DarwinLoadControl(
          preferredForwardBufferDuration: _forwardBufferDuration,
        ),
      ),
    );
  }

  /// Explicitly applies this app's Android audio attributes (the same
  /// ones `AudioSessionConfiguration.music()` — see
  /// `_configureAudioSession` — carries) to the current player, awaited
  /// to completion before this method returns.
  ///
  /// WHY this exists, given `_buildPlayer` already disables `just_audio`'s
  /// automatic version of this: found by actually running the
  /// "Tocar rádio atual" home-screen shortcut on a cold start on a real
  /// Android emulator, which failed with an unhandled
  /// `PlayerInterruptedException: Loading interrupted` — reproducible on
  /// that path, but never on the ordinary "open the app, tap Play" path.
  /// Root cause, confirmed by reading `just_audio`'s own source
  /// (`AudioPlayer._setPlatformActive`): `build()` calls
  /// `_configureAudioSession()` without awaiting it (it must return a
  /// `PlayerState` synchronously), and on a quick-action cold start,
  /// `playFromQuickAction()` can call `_player.setUrl()` within
  /// milliseconds of that — before `_configureAudioSession()`'s chain
  /// (and `just_audio`'s automatic reaction to it) has settled. Both
  /// `setUrl()` and an audio-attributes update start their own
  /// "activation" on the same player, tracked by one shared counter; an
  /// older activation still in flight when a newer one starts is
  /// silently interrupted. On the ordinary open-app-then-tap-Play path
  /// there is enough of a gap between app launch and the tap for this to
  /// never collide — which is exactly why this was easy to miss until
  /// the quick-action path was actually tested end to end.
  /// Calling this explicitly and awaiting it *before* `setUrl` (see
  /// `_attemptConnect`) makes the two activations sequential instead
  /// of concurrent, which removes the race rather than narrowing it.
  /// Cheap to call on every load: `AudioPlayer.setAndroidAudioAttributes`
  /// already no-ops if the attributes are unchanged from last time.
  Future<void> _applyAndroidAudioAttributes() {
    return _player.setAndroidAudioAttributes(const AndroidAudioAttributes(
      contentType: AndroidAudioContentType.music,
      usage: AndroidAudioUsage.media,
    ));
  }

  void _attachIcyMetadataListener() {
    _icySubscription = _player.icyMetadataStream.listen((metadata) {
      final title = metadata?.info?.title?.trim();
      final hasTitle = title != null && title.isNotEmpty;
      if (hasTitle) _resetFailureStreak();
      // A real title arriving is only possible from a live, actually
      // streaming connection — the same "a genuine success signal must
      // win over a stale error" reasoning as _attachPlayerStateListener
      // (see its comment for the full story), just from a second,
      // independent signal. Without this, the exact symptom seen while
      // diagnosing this was "TOCANDO AGORA" showing a real, updating
      // song title at the same time the "Não foi possível tocar" banner
      // was still on screen.
      state = state.copyWith(
        isPlaying: hasTitle ? true : state.isPlaying,
        isLoading: hasTitle ? false : state.isLoading,
        nowPlayingTitle: hasTitle ? title : null,
        errorMessage: hasTitle ? null : state.errorMessage,
      );
      _audioHandler?.updateNowPlayingTitle(title);
    });
  }

  /// Estimates data usage as `bitrate × time played`, rather than counting
  /// real network bytes, because
  /// `just_audio` does not expose byte-level download stats through
  /// one API across iOS/Android/web, and intercepting the stream
  /// ourselves would mean running a local proxy for every station — a lot
  /// of moving parts for a "roughly how much data am I using" estimate.
  /// For the constant-bitrate streams internet radio almost always uses,
  /// this estimate is accurate to within a few percent.
  void _startDataUsageTicker() {
    const tick = Duration(seconds: 5);
    _dataUsageTimer = Timer.periodic(tick, (_) {
      final station = state.currentStation;
      if (!state.isPlaying || station == null || station.bitrateKbps <= 0) return;

      final bytesPerSecond = (station.bitrateKbps * 1000) / 8;
      final bytes = (bytesPerSecond * tick.inSeconds).round();
      ref.read(settingsProvider.notifier).addDataUsage(bytes);
    });
  }

  /// Sets the app's audio session to a standard media-playback
  /// configuration, which is what makes audio default to the speaker
  /// (rather than, say, the earpiece) in the first place — and forces
  /// routing to the speaker (or releases that force) to match
  /// `state.speakerOn`, even with a Bluetooth/wired headset connected, on
  /// both platforms.
  ///
  /// WHY iOS needs a whole extra category switch to do the same thing
  /// Android does in one call: iOS's override API,
  /// `AVAudioSession.overrideOutputAudioPort`, only works under the
  /// `playAndRecord` category — an Apple restriction, confirmed in their
  /// own docs, not a limitation of this app or of `audio_session`. This
  /// app otherwise runs under plain `playback` (see
  /// `AudioSessionConfiguration.music()`), the correct category for a
  /// radio that never records anything, so forcing the speaker means
  /// temporarily switching to `playAndRecord` — with
  /// `allowBluetoothA2dp` kept on so a *non-forced* Bluetooth route still
  /// gets full-quality stereo instead of the old mono call-quality link
  /// `playAndRecord` defaults Bluetooth to — and back to `playback` the
  /// moment "Viva-voz" is turned off. This is genuinely a *recording*
  /// category as far as iOS is concerned even though nothing here ever
  /// taps the microphone, which is why `Info.plist` now carries
  /// `NSMicrophoneUsageDescription` (required the instant this category
  /// is set, regardless of whether recording ever happens — see that
  /// key's own comment in `Info.plist`) and why this only switches
  /// category when actually forcing the speaker, not permanently: no
  /// reason to carry a recording-capable session for the common case
  /// where "Viva-voz" is off.
  Future<void> _configureAudioSession() async {
    final session = await AudioSession.instance;
    final forceSpeaker = state.speakerOn;
    const musicConfig = AudioSessionConfiguration.music();

    if (!kIsWeb && Platform.isIOS && forceSpeaker) {
      await session.configure(musicConfig.copyWith(
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.defaultToSpeaker |
            AVAudioSessionCategoryOptions.allowBluetoothA2dp,
      ));
    } else {
      await session.configure(musicConfig);
    }

    if (!kIsWeb && Platform.isIOS) {
      await AVAudioSession().overrideOutputAudioPort(
        forceSpeaker ? AVAudioSessionPortOverride.speaker : AVAudioSessionPortOverride.none,
      );
    }
    if (!kIsWeb && Platform.isAndroid) {
      await _setAndroidForcedSpeaker(forceSpeaker);
    }
  }


  /// Decides whether the phone's own speaker should be forced on, based on
  /// whichever output device is connected right now, and applies it via
  /// [_configureAudioSession] if that changes anything. Called at the start
  /// of every attempt to actually start audio — [playStation] and
  /// `togglePlayPause`'s resume branch — not just once at app startup,
  /// since a person can plug in or remove a device between one play and
  /// the next.
  ///
  /// Replaces the old manual "Viva-voz" button, by explicit request:
  /// instead of the person having to remember to turn it on, the phone's
  /// speaker is forced automatically whenever nothing else is connected to
  /// route audio to (a wired or Bluetooth headset/speaker, a car's
  /// Bluetooth/AUX, a USB or HDMI output, etc.) — and left alone otherwise,
  /// so plugging in a headset before pressing Play still routes there
  /// exactly as expected, with no toggle to remember. [PlayerState.speakerOn]
  /// itself, and the `_configureAudioSession`/`_setAndroidForcedSpeaker`
  /// machinery it drives, are unchanged from the manual-toggle days — only
  /// *what decides* the value changed.
  Future<void> _updateSpeakerForConnectedDevices() async {
    if (kIsWeb) return; // no device-routing concept to react to on web
    bool forceSpeaker;
    try {
      final session = await AudioSession.instance;
      final devices = await session.getDevices(includeInputs: false, includeOutputs: true);
      // AudioDeviceType is the only way audio_session 0.2.4 classifies a
      // device; still the right tool for the job even while marked
      // experimental upstream.
      bool isBuiltIn(AudioDevice device) =>
          // ignore: experimental_member_use
          device.type == AudioDeviceType.builtInSpeaker || device.type == AudioDeviceType.builtInEarpiece;
      forceSpeaker = devices.every(isBuiltIn);
    } catch (_) {
      // Can't tell what's connected right now — leave whatever was last
      // configured alone rather than guessing.
      return;
    }
    if (forceSpeaker == state.speakerOn) return; // already configured this way
    state = state.copyWith(speakerOn: forceSpeaker);
    await _configureAudioSession();
  }

  /// Forces Android's audio output to the built-in speaker by
  /// temporarily switching the *whole app's* audio mode to
  /// `MODE_IN_COMMUNICATION` — a real, if slightly invasive, trick, used
  /// only because two more targeted attempts were each tried first and
  /// each confirmed not to work:
  ///
  /// 1. `AudioManager.setSpeakerphoneOn` — the traditional API — turned
  ///    out to be a *call*-audio-routing API: Android only documents,
  ///    and only actually applies, its effect while the audio mode is
  ///    already `MODE_IN_CALL`/`MODE_IN_COMMUNICATION`, not the
  ///    `MODE_NORMAL` this app's ordinary media playback runs in.
  ///    Confirmed by hand on a real device with real wired headphones
  ///    connected: tapping "Viva-voz" did nothing at all.
  /// 2. `AudioManager.setCommunicationDevice` (API 31+) looked like the
  ///    modern fix — until reading Android's own documentation closely:
  ///    it is *also* scoped to "communication use cases", and its own
  ///    docs state priority goes "to the application currently
  ///    controlling the audio mode — specifically, the latest
  ///    application having selected mode `MODE_IN_COMMUNICATION` or
  ///    `MODE_IN_CALL`". Since this app never left `MODE_NORMAL`, the
  ///    call was a no-op — confirmed by hand on a real, current-Android
  ///    device: still nothing happened.
  ///
  /// Both (1) and (2) share the same root cause, so the actual fix
  /// addresses that root cause directly: switch to
  /// `MODE_IN_COMMUNICATION` first — which makes this app "the
  /// application controlling the audio mode" per that same
  /// documentation — *then* call `setSpeakerphoneOn`/
  /// `setCommunicationDevice`, which now genuinely apply. All three
  /// calls are `audio_session`'s `AndroidAudioManager`, still no
  /// native/platform-channel code. **Known trade-off, accepted by
  /// explicit user request after (1) and (2) both failed on a real
  /// device:** switching `AudioManager` mode away from `MODE_NORMAL`
  /// can cause a brief audio glitch/interruption at the moment of the
  /// switch, and may affect how other apps' audio focus behaves while
  /// active — real, but judged an acceptable cost for "Viva-voz"
  /// actually working, since it only happens while the toggle is
  /// explicitly on. Mode is switched back to `.normal` the instant
  /// "Viva-voz" turns off — see the `else` branch below — never left in
  /// the call-like mode by default (same "off is the neutral,
  /// side-effect-free state" principle as everywhere else "Viva-voz"
  /// touches).
  Future<void> _setAndroidForcedSpeaker(bool forceSpeaker) async {
    final manager = AndroidAudioManager();
    if (forceSpeaker) {
      // The mode switch is what actually makes the two calls below do
      // anything at all — see this method's own doc comment for the
      // full story confirmed against Android's own documentation.
      await manager.setMode(AndroidAudioHardwareMode.inCommunication);
      await manager.setSpeakerphoneOn(true);
      try {
        final devices = await manager.getAvailableCommunicationDevices();
        AndroidAudioDeviceInfo? speaker;
        for (final device in devices) {
          if (device.type == AndroidAudioDeviceType.builtInSpeaker) {
            speaker = device;
            break;
          }
        }
        if (speaker != null) {
          await manager.setCommunicationDevice(speaker);
        }
      } catch (_) {
        // setCommunicationDevice/getAvailableCommunicationDevices require
        // API 31 — setSpeakerphoneOn above (now actually effective,
        // thanks to the mode switch) is what carries this on older
        // devices.
      }
    } else {
      try {
        await manager.clearCommunicationDevice();
      } catch (_) {
        // API < 31 — nothing was ever set via this call to clear.
      }
      await manager.setSpeakerphoneOn(false);
      // Back to MODE_NORMAL — leaving the app in a call-like audio mode
      // by default (the moment "Viva-voz" is off) would be exactly the
      // kind of always-on side effect this project avoids elsewhere.
      await manager.setMode(AndroidAudioHardwareMode.normal);
    }
  }

  /// Pre-selects a station (so the home screen has something to show)
  /// without loading or playing audio. Called every time the visible
  /// station list changes (see HomeScreen) — not just once — so that
  /// switching states before ever pressing Play updates the preview to
  /// match the new state instead of leaving last state's station on
  /// screen. See [togglePlayPause], which knows to actually load the
  /// stream the first time Play is pressed on a station selected this way.
  ///
  /// WHY this checks `_loadedStationId` rather than "is currentStation
  /// null": once a station has actually been loaded into the player
  /// (played at least once, even if paused since), it must never be
  /// silently swapped out just because the user browsed to a different
  /// state's list — that would be surprising. Before that point, though,
  /// there is nothing playing to protect, so keeping the preview in sync
  /// with the visible list is the more correct behavior.
  Future<void> setInitialStation(List<RadioStation> visibleStations) async {
    if (state.currentStation != null || _resolvingInitialStation) return;
    _resolvingInitialStation = true;
    try {
      final saved = await ref.read(storageServiceProvider).getLastStation();
      // Looked up in the full list, not just the visible (Favoritas/Todas)
      // one: the remembered station must come back even if the person
      // closed the app on "Todas" and reopened it on a tab that hides it.
      final pool = ref.read(stationsProvider).value ?? visibleStations;
      final station = pickInitialStation(pool, saved) ?? pickInitialStation(visibleStations, saved);
      // Re-checked after the await: a playStation call (quick action,
      // widget) may have set a station while the disk read was pending.
      if (station == null || state.currentStation != null) return;
      state = state.copyWith(currentStation: station);
      _persistLastStation(station);
    } finally {
      _resolvingInitialStation = false;
    }
  }

  bool _resolvingInitialStation = false;

  Future<void> playStation(RadioStation station) async {
    final token = ++_loadToken;
    state = state.copyWith(
      currentStation: station,
      isLoading: true,
      nowPlayingTitle: null, // switching stations — the old song title no longer applies
      errorMessage: null,
    );
    _persistLastStation(station);
    _audioHandler?.setMediaItemForStation(station);
    // Deliberately here, not spread across every entry point that can
    // start playback (the list, next/previous, the lock-screen/widget/
    // Android Auto, the quick action) — this is the single choke point
    // all of them already funnel through, so one call covers "which
    // station is most listened to" for every single one of them.
    ref.read(analyticsServiceProvider).logStationPlayed(station);
    await _updateSpeakerForConnectedDevices();
    await _connectWithRetry(station, token: token);
  }

  /// Remembers [station] as "the one to resume" — read back by
  /// [playFromQuickAction] when the home-screen shortcut is tapped after
  /// the app was fully closed, when there is no in-memory state left to
  /// fall back on. See `StorageService.getLastStation`/`setLastStation`.
  void _persistLastStation(RadioStation station) {
    ref.read(storageServiceProvider).setLastStation(station);
  }

  /// Called from the "Tocar rádio atual" home-screen shortcut (see
  /// `QuickActionsService` and `main.dart`). Plays whatever is already
  /// current if the app was already running, or — if the app was fully
  /// closed and this tap is what launched it, so [PlayerState.currentStation]
  /// is still `null` — falls back to the last station persisted by
  /// [_persistLastStation].
  Future<void> playFromQuickAction() async {
    final station = state.currentStation ?? await ref.read(storageServiceProvider).getLastStation();
    if (station == null) return;
    await playStation(station);
  }

  /// Tracks which station's stream is actually loaded into [_player], so
  /// [togglePlayPause] can tell "pre-selected but never loaded" (via
  /// [setInitialStation]) apart from "already loaded, just paused".
  String? _loadedStationId;

  /// Bumped every time a new attempt to reach "playing" starts — [playStation]
  /// and `togglePlayPause`'s resume branch each capture the post-increment
  /// value as their own `token` before awaiting anything, and so does
  /// `_reconnectAfterDrop` when the stream drops unexpectedly mid-play.
  /// `_attemptConnect`/`_connectWithRetry` and [_setPlaybackError] compare
  /// their `token` against the current value
  /// of this field before writing to [state]: if a *newer* attempt has since
  /// started, this one's result — success or failure — is stale and gets
  /// discarded instead of applied.
  ///
  /// WHY this exists: switching stations quickly after one fails to connect
  /// used to leave the error banner (and a non-playing button) stuck on
  /// screen indefinitely even though the newly picked station was genuinely
  /// playing underneath it — reported directly. Root cause: a slow-to-fail
  /// connection attempt for the *old* station is not actually cancelled when
  /// the person switches away from it (see `_attachPlayerStateListener`'s own
  /// doc on Dart's `Future.timeout()` not cancelling the underlying native
  /// call) — so its `_setPlaybackError()` call could still land *after* the
  /// new station's own successful load had already updated [state], silently
  /// overwriting a correct, playing state with a stale error that no longer
  /// applied to anything on screen. Same shape of race as
  /// `_HomeWidgetSyncState._updateGeneration` and
  /// `RadioAudioHandler._rebuildMediaItem`'s own staleness guards elsewhere
  /// in this app — a generation counter, not a station-id comparison, because
  /// even re-selecting the *same* station moments later should still count
  /// as a newer attempt superseding the one before it.
  int _loadToken = 0;

  /// How many connection attempts have failed *in a row*, with no
  /// success in between. Reset to 0 by [_resetFailureStreak] (called
  /// from every place a success signal can arrive — see its own doc)
  /// and bumped by [_setPlaybackError]; once it reaches 3,
  /// `_setPlaybackError` bumps [PlayerState.stationsOfflineTrigger] (and
  /// resets this back to 0, so the *next* run of 3 failures fires again)
  /// for the home screen to show `StationsOfflineDialog`. Deliberately
  /// kept as a private field here, not part of [PlayerState] itself —
  /// nothing outside this notifier needs the raw in-progress count, only
  /// the "should the dialog show now" event that crossing 3 produces.
  int _consecutiveFailures = 0;

  /// Called from every place a genuinely successful connection is
  /// confirmed (a fresh `play()` succeeding, a resume succeeding, or one
  /// of the two independent late-success signals in
  /// [_attachPlayerStateListener]/[_attachIcyMetadataListener]) — see
  /// [_consecutiveFailures]'s own doc for what this resets and why.
  void _resetFailureStreak() {
    _consecutiveFailures = 0;
  }

  /// How long we wait for a stream to start responding before giving up.
  ///
  /// WHY this exists: without it, a station whose server accepts the
  /// connection but never actually sends audio (which does happen with
  /// dead or misconfigured streams that Radio Browser's own health check
  /// has not caught yet) — or, as found while testing this app in a
  /// browser, `just_audio`'s web backend occasionally hanging on `play()`
  /// itself even after `setUrl` already succeeded — leaves the player
  /// awaiting forever. The user would be stuck looking at a spinning Play
  /// button with no feedback and no way out except restarting the app. A
  /// timeout on each step turns that into the same friendly "could not
  /// play this station" error as any other failure.
  ///
  /// WHY 20 seconds and not something shorter: on iOS, `setUrl()`'s
  /// Future only resolves once AVFoundation reports the player item as
  /// ready, which for a live radio stream (no fixed duration) genuinely
  /// varies with how quickly that particular station's server responds
  /// — measured by hand at 8–10 seconds for some perfectly healthy
  /// stations. This timeout existing at all does not fully protect
  /// against a slow-but-working stream anymore, since a real success
  /// arriving after this fires is now recovered instead of stuck behind
  /// a stale error — see `_attachPlayerStateListener` and
  /// `_attachIcyMetadataListener` — but a timeout still shorter than
  /// real connections regularly need would mean showing (and dismissing
  /// a moment later) an error unnecessarily on every single one of them.
  static const _connectTimeout = Duration(seconds: 20);

  /// How long a mid-playback drop keeps retrying — see
  /// `_connectWithRetry`/`_reconnectAfterDrop` — before finally giving up
  /// and falling back to the ordinary error/play state. Chosen to
  /// comfortably fit several full connection attempts (each up to
  /// [_connectTimeout]) plus the pauses between them: long enough to ride
  /// out a brief real-world network blip (elevator, tunnel, Wi-Fi
  /// handoff) without ever bothering the person with an error they never
  /// needed to see.
  static const _reconnectRetryWindow = Duration(seconds: 60);

  /// Pause between one failed attempt and the next inside
  /// `_connectWithRetry`'s loop — avoids hammering the stream URL back to
  /// back while the network is still down.
  static const _reconnectRetryDelay = Duration(seconds: 5);

  /// A single attempt to load and play [station]. Never touches
  /// `errorMessage`/`stationsOfflineTrigger` itself on failure — that is
  /// `_connectWithRetry`'s job, once *all* retries (not just this one
  /// attempt) are exhausted — so this can be called repeatedly from a
  /// retry loop without flashing an error on screen between attempts.
  Future<_ConnectOutcome> _attemptConnect(RadioStation station, {required int token}) async {
    try {
      await _applyAndroidAudioAttributes();
      await _player.setUrl(station.streamUrl).timeout(_connectTimeout);
      // A newer call (a later station pick, or a newer retry loop) already
      // took over `_player` while this `setUrl` was in flight — see
      // `_loadToken`'s own doc. Recording `_loadedStationId`/resetting the
      // failure streak for a station that isn't even loaded anymore would
      // be wrong, not just a stale UI write, so this bails out before either.
      if (token != _loadToken) return _ConnectOutcome.superseded;
      _loadedStationId = station.id;
      _resetFailureStreak();
      // No per-station player-level volume to set here: the player is
      // always at full gain, and loudness is controlled entirely through
      // the phone's system volume — see SystemVolumeService.
      await _player.play().timeout(_connectTimeout);
      if (token != _loadToken) return _ConnectOutcome.superseded; // superseded while `play()` was in flight
      // `errorMessage: null` here is deliberate: this is a genuine "we
      // just succeeded" moment, so any error left over from an earlier
      // failed attempt at this same station must be cleared — omitting
      // it would leave a station that failed once and then genuinely
      // started playing on a later retry still showing the old "Não foi
      // possível tocar" banner over live audio.
      //
      // WHY `isLoading` isn't simply set to `false` here: `play()`'s
      // Future resolves as soon as playback is *requested*, not once
      // audio is actually flowing — by direct report, switching
      // stations showed the pause icon (implying already playing)
      // while the new stream was still connecting. Leaving `isLoading`
      // true until `_player.processingState` genuinely reaches `ready`
      // keeps the spinner up for that gap; `_attachPlayerStateListener`
      // is what clears it the moment real audio is ready, from the
      // player's own state stream (the same signal used there — see
      // its own `readyToPlay` doc — rather than duplicating that check
      // any differently here).
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

  /// Attempts to connect [station] and, if that first attempt fails,
  /// keeps quietly retrying — same station, `isLoading` spinner up the
  /// whole time, no error shown — every [_reconnectRetryDelay] until
  /// [_reconnectRetryWindow] has elapsed, before finally reporting the
  /// ordinary error state via [_setPlaybackError].
  ///
  /// Used both for a fresh connection ([playStation], which every way of
  /// starting a station already funnels through: the list, next/previous,
  /// the quick action, Android Auto, the widget) and for reconnecting
  /// after the stream drops unexpectedly mid-play (see
  /// [_reconnectAfterDrop]). In both cases the most common real-world
  /// cause of a failed stream is a brief network blip, not a station that
  /// is genuinely gone — by explicit request, both should patiently keep
  /// trying before bothering the person with an error, rather than
  /// reporting failure after a single attempt.
  Future<void> _connectWithRetry(RadioStation station, {required int token}) async {
    final deadline = DateTime.now().add(_reconnectRetryWindow);
    while (true) {
      if (token != _loadToken) return;
      final outcome = await _attemptConnect(station, token: token);
      if (outcome != _ConnectOutcome.failed) return; // success, or superseded by a newer attempt
      if (!DateTime.now().isBefore(deadline)) break;
      await Future.delayed(_reconnectRetryDelay);
    }
    _setPlaybackError(token);
  }

  /// Shared failure state for `_connectWithRetry` (used by [playStation]
  /// and `_reconnectAfterDrop`) and [togglePlayPause]'s resume path — all
  /// can fail the same way (a stream that will not connect or will not
  /// start), so they report it the same way. `_connectWithRetry` only
  /// calls this once, after every retry in its window has already failed
  /// — not once per individual attempt.
  ///
  /// WHY this checks `_player.playing` before doing anything: a
  /// `.timeout()` firing here does not prove the connection failed —
  /// see `_attachPlayerStateListener`'s WHY comment for the full story
  /// of why a late, genuine success can arrive after this is called.
  /// That listener corrects a stale error the *next* time the player's
  /// state actually changes, but if playback is already stable (no
  /// further change coming any time soon), an error written here would
  /// otherwise sit on screen indefinitely over genuinely working audio
  /// — confirmed by hand: a station played correctly and continuously
  /// (per `xcrun simctl ... log stream`) while this exact banner sat on
  /// screen, with no further player-state event to ever clear it. This
  /// early return is what actually prevents that, by checking the
  /// player's real state directly instead of only reacting to it.
  void _setPlaybackError(int token) {
    // A stale write from a load attempt that's no longer the most recent —
    // e.g. this station's connection finally errored out well after the
    // person had already switched to (and successfully loaded) a different
    // one. Without this check, this call could clobber a station that is,
    // right now, genuinely playing correctly, with an error message that
    // no longer applies to anything on screen — see `_loadToken`'s own doc
    // for the full, directly-reported symptom this fixes.
    if (token != _loadToken) return;

    // WHY `readyToPlay` (the same "playing AND actually ready" signal
    // _attachPlayerStateListener already uses), not just `_player.playing`:
    // `just_audio`'s `playing` flag is intent ("should be playing"), which
    // just_audio deliberately carries across `setUrl()` — so switching from
    // a station that was genuinely playing to a new one that then times out
    // left `_player.playing` stale-true from the *old* station, even though
    // the *new* one never got anywhere near ready. That stale flag made this
    // method return before ever touching `state` — reported directly as an
    // infinite loading spinner (isLoading stuck true forever, no error, no
    // dialog) whenever a failing station was picked right after a working
    // one. Checking real readiness instead of raw intent means this only
    // bails when the player is truly, currently delivering audio.
    if (_player.playing && _player.processingState == ProcessingState.ready) return;

    // Every 3rd failure *in a row* (no success in between — see
    // _consecutiveFailures' own doc) bumps stationsOfflineTrigger, which
    // the home screen watches to show StationsOfflineDialog, and resets
    // the streak so the next run of 3 fires it again instead of firing
    // on every single failure from here on. A first attempt at this
    // feature fired on every single failure instead — explicit user
    // feedback afterward was that this was a misunderstanding of the
    // original request (a stuck-loading station should get *some*
    // visible feedback, which the inline `ErrorBanner` below already
    // gives it) and that the modal was only ever meant to come back
    // after a real run of 3, same as its original design.
    _consecutiveFailures++;
    final justReachedThree = _consecutiveFailures >= 3;
    if (justReachedThree) _consecutiveFailures = 0;

    state = state.copyWith(
      isPlaying: false,
      isLoading: false,
      nowPlayingTitle: null,
      errorMessage: 'Rádio não disponível no momento. Tente outra estação.',
      stationsOfflineTrigger: justReachedThree ? state.stationsOfflineTrigger + 1 : state.stationsOfflineTrigger,
    );
  }

  Future<void> togglePlayPause() async {
    final station = state.currentStation;
    if (station == null) return;

    // First tap on a station that was only pre-selected (see
    // setInitialStation) — nothing is loaded into the player yet.
    if (_loadedStationId != station.id) {
      await playStation(station);
      return;
    }

    if (state.isPlaying) {
      // Pausing is not expected to hang the way starting playback can —
      // no network round-trip is involved — so it is not wrapped in the
      // same timeout/loading treatment as resuming, below.
      await _player.pause();
      state = state.copyWith(isPlaying: false);
      return;
    }

    // Resuming an already-loaded stream still talks to the network
    // (internet radio has no local buffer to fall back on once fully
    // paused), so it gets the same loading indicator and timeout
    // protection as a fresh `playStation` call — without this, a stall
    // here left the Play button looking simply unresponsive, with no
    // spinner and no error, which is worse than the loading state it
    // now shows. Also takes its own `_loadToken` — see that field's own
    // doc — so a station switch that happens while this resume is still
    // in flight can supersede it the same way it can supersede a fresh
    // `playStation` call, instead of this call's late result clobbering
    // whatever the person switched to.
    final token = ++_loadToken;
    state = state.copyWith(isLoading: true);
    await _updateSpeakerForConnectedDevices();
    try {
      await _player.play().timeout(_connectTimeout);
      if (token != _loadToken) return; // superseded by a station switch while resuming
      _resetFailureStreak();
      // A successful resume must clear any error left over from an
      // earlier failed attempt at this station, same as
      // _attemptConnect's own success path.
      state = state.copyWith(
        isPlaying: true,
        // Same reasoning as `_attemptConnect`'s identical check: `play()`
        // resolving doesn't mean audio is actually flowing yet, so the
        // spinner stays up until `_player.processingState` genuinely
        // reaches `ready` (or `_attachPlayerStateListener` confirms it
        // from the player's own state stream, whichever notices first).
        isLoading: _player.processingState != ProcessingState.ready,
        // `nowPlayingTitle: null`, not left alone, by explicit request:
        // this app is live radio, not an on-demand recording — whatever
        // song was showing when the person paused is almost certainly
        // not what's airing anymore by the time they resume, especially
        // after a real pause (switching apps, coming back later), not a
        // quick tap. Nulling it here mirrors what `playStation` already
        // does when switching stations ("the old song title no longer
        // applies") and lets `_attachIcyMetadataListener` repopulate it
        // with the genuinely current title as soon as the resumed
        // stream's next ICY metadata block arrives — in the meantime,
        // the "Tocando agora" block just hides itself, same as any other
        // station that hasn't sent a title yet (see PlayerState's own
        // "Now playing" doc), instead of confidently showing stale info.
        nowPlayingTitle: null,
        errorMessage: null,
      );
      // Same reasoning as the state update above — the lock-screen/
      // notification title is a separate piece of state RadioAudioHandler
      // caches on its own (see its `_songTitle` field), so clearing this
      // app's own `state.nowPlayingTitle` alone would leave the
      // notification showing the pre-pause song indefinitely.
      _audioHandler?.updateNowPlayingTitle(null);
    } catch (_) {
      _setPlaybackError(token);
    }
  }

  Future<void> playNext() => _shiftStation(1);
  Future<void> playPrevious() => _shiftStation(-1);

  /// Moves to the next/previous station within whatever list is currently
  /// visible (respecting the Favoritas/Todas filter) — see
  /// [visibleStationsProvider].
  Future<void> _shiftStation(int delta) async {
    final stations = ref.read(visibleStationsProvider).value;
    if (stations == null || stations.isEmpty) return;

    final currentId = state.currentStation?.id;
    final currentIndex = currentId == null
        ? -1
        : stations.indexWhere((s) => s.id == currentId);

    final rawIndex = (currentIndex + delta) % stations.length;
    final nextIndex = rawIndex < 0 ? rawIndex + stations.length : rawIndex;
    await playStation(stations[nextIndex]);
  }

  /// Volume always moves in 10% steps — a deliberate choice over a
  /// free-dragging slider, since a fixed step is far easier to hit
  /// precisely with a large touch target than a slider thumb is, for the
  /// app's target audience.
  ///
  /// This sets the phone's actual system volume (see
  /// SystemVolumeService), not a player-internal gain — the update to
  /// `state.volumePercent` here is optimistic (applied immediately, for
  /// a responsive-feeling button) and will be confirmed/corrected by the
  /// [SystemVolumeService.listen] callback registered in [build] once the
  /// platform reports the change back.
  void setVolumePercent(int percent) {
    final clamped = percent.clamp(0, 100);
    state = state.copyWith(volumePercent: clamped);
    _volumeService.setVolumePercent(clamped);
  }

  void increaseVolume() => setVolumePercent(state.volumePercent + 10);
  void decreaseVolume() => setVolumePercent(state.volumePercent - 10);

  /// Clears a stale "Rádio não disponível" banner — called when the
  /// person picks a different state in Settings. Reported directly: the
  /// error banner (and its underlying `errorMessage`) belongs to the
  /// *previous* state's station, and switching state fetches a whole new
  /// station list, so leaving it on screen reads as if the freshly
  /// arrived list — or whatever station happens to still be loaded — is
  /// also broken, which is not necessarily true. Deliberately narrow:
  /// this only clears the visible error text — it does not touch
  /// `isPlaying`/`isLoading`/`currentStation`, since whatever is
  /// currently loaded keeps playing (or not) exactly as it was; picking
  /// a new state on its own is not a reason to stop it.
  void clearError() {
    if (state.errorMessage == null) return;
    state = state.copyWith(errorMessage: null);
  }

  /// Called by [_AppLifecycleSync] in `main.dart` every time the app
  /// returns to the foreground (`AppLifecycleState.resumed`) — iOS only,
  /// see below for why.
  ///
  /// WHY this exists, reported directly: on iOS, playing a station and
  /// locking the phone shows the expected lock-screen/Control Center
  /// controls (title, song, play/pause, skip). But switching away to a
  /// *different* app (even one that never plays audio itself, e.g.
  /// Safari) and then back to Nice Radio, then locking the phone again,
  /// shows *no* controls at all — audio keeps playing correctly the
  /// entire time, only the lock-screen surface is gone. The only thing
  /// that brought it back was toggling "Viva-voz" on and off, which was
  /// the actual clue: that toggle's only real effect is re-running
  /// `_configureAudioSession()`, so whatever it was accidentally fixing
  /// had to be about the audio session, not playback itself.
  ///
  /// This matches Apple's own documented guidance precisely: an app must
  /// explicitly reactivate its audio session "each time your app becomes
  /// active... the only method guaranteed to be called every time your
  /// app is reactivated under circumstances where your audio session
  /// might have been deactivated in the background" — i.e.
  /// `applicationDidBecomeActive`, Flutter's `AppLifecycleState.resumed`.
  /// iOS can quietly stop considering this app "the" Now Playing app
  /// without ever actually interrupting its audio, and nothing about
  /// ordinary continued playback (no new `PlaybackEvent`, no station or
  /// title change) naturally prompts a re-announcement — confirmed by
  /// reading `audio_session`'s own source: its `configure()` (already
  /// called whenever "Viva-voz" changes) only sets the session
  /// *category*, never reactivates it — `setActive(true)` is a genuinely
  /// separate call this codebase had never made outside of initial
  /// setup. Reactivating it here, plus explicitly re-publishing the
  /// current state via `RadioAudioHandler.refreshNowPlayingInfo`, is a
  /// direct, intentional fix rather than relying on an accidental side
  /// effect of an unrelated feature.
  ///
  /// iOS-only, and a no-op with nothing playing/paused: this bug has
  /// only been reported on iOS (Android's media session handling has not
  /// shown the same symptom), and there is nothing to reclaim if no
  /// station is loaded.
  Future<void> handleAppResumed() async {
    if (kIsWeb || !Platform.isIOS) return;
    if (state.currentStation == null) return;
    // Re-assert the session *category*, not just reactivate it —
    // `setActive(true)` alone was the original fix (see this method's own
    // doc above), confirmed working the first time this bug was reported.
    // A later, direct report of the exact same symptom recurring on a
    // *second* lock (lock → controls show → tap one, app resumes and
    // plays fine → lock again → controls gone) pointed at that fix being
    // incomplete: `setActive(true)` only ever re-activates whatever
    // category is *currently* configured — it does not re-assert what
    // that category actually is. `_configureAudioSession()` does that
    // part (see its own doc), and until now was only ever called from
    // `build()` once at launch and from `_updateSpeakerForConnectedDevices()`
    // when the speaker-forcing decision changes — never as part of this
    // resume path. Calling it here first, before `setActive(true)`, means
    // every resume re-confirms both "what category" and "is it active",
    // not just the second half.
    await _configureAudioSession();
    final session = await AudioSession.instance;
    await session.setActive(true);
    _audioHandler?.refreshNowPlayingInfo();
  }

  /// Sets (or clears, with `minutes == 0`) the sleep timer. Any
  /// previously scheduled timer is cancelled first, so picking a new
  /// duration always replaces the old one rather than stacking.
  void setSleepMinutes(int minutes) {
    _sleepTimer?.cancel();
    state = state.copyWith(sleepMinutes: minutes);

    if (minutes > 0) {
      _sleepTimer = Timer(Duration(minutes: minutes), () async {
        await _player.pause();
        state = state.copyWith(isPlaying: false, sleepMinutes: 0);
      });
    }
  }
}

final playerProvider = NotifierProvider<PlayerNotifier, PlayerState>(
  PlayerNotifier.new,
);
