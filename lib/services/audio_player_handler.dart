// Wraps the app's single `just_audio` AudioPlayer so `audio_service` can
// mirror its state into the OS's own media notification / lock-screen
// controls, and forward taps on those controls (play, pause, stop, and
// skip-to-next/previous — which switch station, see [skipToNext]) back
// into the same player. This is what lets the radio keep playing — and
// stay controllable — while Nice Radio itself is backgrounded or the
// phone is locked.
//
// WHY this wraps PlayerNotifier's existing AudioPlayer instead of owning
// a second one: audio_service and just_audio both need to observe and
// control the *same* playback, not two independent players that could
// drift out of sync (e.g. the notification saying "tocando" while the
// app's own screen shows paused, or vice versa). PlayerNotifier still
// owns the player's lifecycle (creation, disposal) — this handler only
// observes and relays.
import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart' show ValueChanged;
import 'package:just_audio/just_audio.dart';

import '../models/radio_station.dart';
import 'station_artwork_service.dart';

class RadioAudioHandler extends BaseAudioHandler {
  final AudioPlayer _player;
  final _artworkService = StationArtworkService();

  RadioStation? _station;
  String? _songTitle;
  List<RadioStation> _browsableStations = const [];

  /// Set by [PlayerNotifier] right after it registers this handler.
  /// Called when Android Auto's "Now Playing"/browse UI taps a station
  /// from [getChildren]'s list — see [playFromMediaId]. A plain callback
  /// rather than this handler reaching into Riverpod itself, same
  /// reasoning as everywhere else in this file: the handler only
  /// observes and relays, [PlayerNotifier] still owns what "play this
  /// station" actually means (persisting it, audio attributes, etc.).
  ValueChanged<RadioStation>? onPlayStation;

  RadioAudioHandler(AudioPlayer player) : _player = player {
    player.playbackEventStream.listen((_) => _broadcastState());
  }

  /// Re-publishes the current playback state and media item to the OS,
  /// without anything about actual playback having changed — used to
  /// reclaim iOS's "Now Playing App" status after it is silently dropped.
  /// See `PlayerNotifier.handleAppResumed`'s doc for the full story: this
  /// app can keep playing correctly the entire time and still lose its
  /// lock-screen/Control Center controls, because iOS's decision of
  /// which app currently "owns" that surface is separate from whether
  /// audio is actually playing, and nothing about ordinary playback
  /// continuing (no new `PlaybackEvent`, no station/title change) ever
  /// prompts this handler to speak up again on its own.
  void refreshNowPlayingInfo() {
    _broadcastState();
    unawaited(_rebuildMediaItem());
  }

  /// Mirrors a `just_audio` playback event into the `PlaybackState` the OS
  /// notification/lock-screen reads. Listens to the player directly
  /// (rather than only reacting to calls made through this handler) so a
  /// change made from the app's own UI shows up in the notification just
  /// as reliably as one triggered from the notification itself.
  ///
  /// Declares `skipToPrevious`/`skipToNext` alongside play/pause/stop —
  /// without them in `controls`, `audio_service` never enables iOS's
  /// `MPRemoteCommandCenter.previousTrackCommand`/`nextTrackCommand` (or
  /// Android's equivalent MediaSession actions), so the lock screen's
  /// prev/next buttons would be visible but inert. See [skipToPrevious]/
  /// [skipToNext] for what they actually do — this app has no "queue" in
  /// the music-player sense, so they switch station instead of track.
  void _broadcastState() {
    final playing = _player.playing;
    final station = _station;
    final queueIndex = station == null
        ? null
        : _browsableStations.indexWhere((s) => s.streamUrl == station.streamUrl);
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        playing ? MediaControl.pause : MediaControl.play,
        MediaControl.skipToNext,
        MediaControl.stop,
      ],
      androidCompactActionIndices: const [0, 1, 2],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: playing,
      // See updateBrowsableStations' doc for why Android Auto specifically
      // needs a real queue index here, not just the skip controls above.
      // -1 (not found — e.g. before the browsable list has loaded at all)
      // becomes null, since a negative index isn't a valid queue position.
      queueIndex: queueIndex == null || queueIndex < 0 ? null : queueIndex,
    ));
  }

  /// Sets the notification's station name/genre/logo. Called by
  /// [PlayerNotifier] whenever the current station changes. Clears any
  /// song title from the previous station — see [updateNowPlayingTitle].
  void setMediaItemForStation(RadioStation station) {
    _station = station;
    _songTitle = null;
    unawaited(_rebuildMediaItem());
  }

  /// Refines the notification with the actual song title, when the
  /// stream provides one via ICY metadata — the same information the
  /// home screen's "Tocando agora" block shows. `null`/empty reverts the
  /// notification to just the station name.
  void updateNowPlayingTitle(String? title) {
    _songTitle = (title == null || title.isEmpty) ? null : title;
    unawaited(_rebuildMediaItem());
  }

  Future<void> _rebuildMediaItem() async {
    final station = _station;
    if (station == null) return;
    final songTitle = _songTitle;
    final artCacheFile = await _resolveArtCacheFile(station);
    // Guards against a slower, earlier call finishing after a newer one
    // (e.g. skipping stations quickly while a fallback image is still
    // being generated for the previous one) and overwriting the media
    // item with stale station/title data — see `_resolveArtCacheFile`'s
    // doc for why this method is async at all now.
    if (_station != station || _songTitle != songTitle) return;
    mediaItem.add(MediaItem(
      id: station.streamUrl,
      // Song title takes the headline spot when known (like a music app
      // showing "track — artist"); otherwise the station itself is the
      // headline, with its genre as the subtitle.
      title: songTitle ?? station.name,
      artist: songTitle != null ? station.name : station.genre,
      // WHY both `artUri` *and* `extras['artCacheFile']` point at the same
      // local file: confirmed by reading `audio_service 0.18.19`'s native
      // iOS source (AudioServicePlugin.m) — its `setMediaItem` handler
      // only even looks at `extras['artCacheFile']` when `artUri` is
      // non-null (an `artUri == null` guard wraps that whole block).
      // `artUri`'s own value is otherwise unused for a local file (see
      // StationArtworkService's doc for why a remote `https://` URL alone
      // never gets fetched), so this is set purely to satisfy that gate —
      // found by hand, from a real "favicon works, generated artwork
      // silently doesn't" split, not documented anywhere in the package.
      // Android's own native side (AudioService.java) has no such gate —
      // it reads `extras['artCacheFile']` unconditionally — so `artUri`
      // is a harmless no-op there, kept only for iOS's sake.
      artUri: artCacheFile == null ? null : Uri.file(artCacheFile),
      extras: artCacheFile == null ? null : {'artCacheFile': artCacheFile},
    ));
  }

  /// A real favicon URL when the station has one; otherwise a generated
  /// "initials" image (see StationArtworkService) so the lock-screen/
  /// notification never shows a blank artwork square. This is the one
  /// place in this file that needs real `await`ing — resolving/generating
  /// the fallback image is genuinely asynchronous — which is why
  /// [_rebuildMediaItem] (and everything that triggers it) is async too.
  /// A real favicon (downloaded) or a generated "initials" image (see
  /// StationArtworkService) — as a local file path passed through
  /// `MediaItem.extras['artCacheFile']`. This is the one place in this
  /// file that needs real `await`ing — resolving/generating/downloading
  /// the artwork is genuinely asynchronous — which is why
  /// [_rebuildMediaItem] (and everything that triggers it) is async too.
  ///
  /// WHY `extras['artCacheFile']`, not `MediaItem.artUri`: confirmed by
  /// reading `audio_service`'s own native source — see this class's own
  /// doc and StationArtworkService's for the full story. A plain `artUri`
  /// (even a real, reachable `https://` favicon URL) is silently never
  /// fetched by this plugin version on either platform; only a local file
  /// path in `extras['artCacheFile']` actually renders.
  Future<String?> _resolveArtCacheFile(RadioStation station) async {
    try {
      return await _artworkService.cachedArtworkFilePath(station);
    } catch (_) {
      return null; // Worst case: the same blank-artwork behavior as before this fix.
    }
  }

  /// Same station → `MediaItem` mapping as [_rebuildMediaItem], minus the
  /// live song title — used for the browse list (see
  /// [updateBrowsableStations]), which lists *other* stations you could
  /// switch to, not the one currently playing, so there is no "now
  /// playing song" to show for any of them.
  MediaItem _stationToMediaItem(RadioStation station) => MediaItem(
        id: station.streamUrl,
        title: station.name,
        artist: station.genre,
        artUri: station.faviconUrl != null ? Uri.tryParse(station.faviconUrl!) : null,
      );

  /// The station list Android Auto's "browse" screen shows — see
  /// [getChildren]. Called by [PlayerNotifier] every time the visible
  /// station list changes (a new state picked, or the list finishing its
  /// first fetch); harmless to call with the same list again.
  ///
  /// WHY the *unfiltered* list for the selected state, not whatever the
  /// phone screen's Favoritas/Todas toggle happens to show: a car
  /// passenger browsing while "Favoritas" is empty (or just has a
  /// different station in mind than whatever the phone was last showing)
  /// should not see an empty or unexpectedly short list — see
  /// `PlayerNotifier`'s own call site for which provider this comes from.
  void updateBrowsableStations(List<RadioStation> stations) {
    _browsableStations = stations;
    // WHY this also publishes `queue` (not just the browse tree above):
    // confirmed against `audio_service`'s own Android Auto example
    // (audio_service-0.18.19/example/lib/example_android_songs.dart),
    // which populates `queue` and sets `queueIndex` on every broadcast —
    // Android Auto's "Now Playing" screen was reported to not show the
    // skip-to-next/previous buttons at all, even though `_broadcastState`
    // already declares `MediaControl.skipToPrevious`/`.skipToNext` (which
    // do reach the phone's own lock-screen/notification correctly, via
    // the actions bitmask those controls produce). A car head unit's Now
    // Playing template is stricter than a phone notification: without an
    // actual queue set on the MediaSession, some implementations treat
    // "nothing to skip to" as reason enough to hide the buttons regardless
    // of the actions bitmask. See `_broadcastState`'s own `queueIndex`.
    queue.add(stations.map(_stationToMediaItem).toList());
  }

  /// Android Auto (and any other media-browser client) calls this to
  /// build its browse UI — first with [AudioService.browsableRootId] to
  /// get the top level, which here is just the flat station list (see
  /// [updateBrowsableStations]). This app has no deeper hierarchy (no
  /// folders/genres to browse into), so any other parent id has nothing
  /// under it.
  @override
  Future<List<MediaItem>> getChildren(String parentMediaId, [Map<String, dynamic>? options]) async {
    if (parentMediaId != AudioService.browsableRootId) return const [];
    return _browsableStations.map(_stationToMediaItem).toList();
  }

  /// Called when a station is tapped from Android Auto's browse list
  /// (built from [getChildren]) or from a media-browser "recent" tile.
  /// [mediaId] is the same `MediaItem.id` set in [_stationToMediaItem] —
  /// each station's stream URL, already used as its id everywhere else in
  /// this handler.
  @override
  Future<void> playFromMediaId(String mediaId, [Map<String, dynamic>? extras]) async {
    for (final station in _browsableStations) {
      if (station.streamUrl == mediaId) {
        onPlayStation?.call(station);
        return;
      }
    }
  }

  /// Lock-screen/notification "next"/"previous" — this app has no queue
  /// or playlist, only "whichever stations are known right now" (the
  /// same list [getChildren] browses), so these switch to the next/
  /// previous station in that list instead of the next/previous track.
  /// Cycling through the *unfiltered* per-state list (not whatever the
  /// phone screen's Favoritas/Todas toggle is showing) mirrors the same
  /// choice [updateBrowsableStations] already made for Android Auto —
  /// someone controlling playback from the lock screen with the phone
  /// locked cannot see, let alone react to, which tab was selected the
  /// last time the app was open.
  @override
  Future<void> skipToNext() => _skipStation(1);

  @override
  Future<void> skipToPrevious() => _skipStation(-1);

  Future<void> _skipStation(int direction) async {
    final station = _station;
    if (station == null || _browsableStations.isEmpty) return;
    final currentIndex = _browsableStations.indexWhere((s) => s.streamUrl == station.streamUrl);
    if (currentIndex == -1) return;
    // Dart's `%` follows Euclidean modulo for a positive divisor, so this
    // wraps correctly in both directions (e.g. -1 % length == length - 1)
    // without a separate "if negative, add length back" step.
    final nextIndex = (currentIndex + direction) % _browsableStations.length;
    onPlayStation?.call(_browsableStations[nextIndex]);
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }
}
