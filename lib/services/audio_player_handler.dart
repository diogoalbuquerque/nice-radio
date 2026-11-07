// `audio_service` handler: mirrors the app's single `just_audio` player into
// the OS media notification / lock screen / Android Auto, and relays their
// controls back. It only observes and relays — `PlayerNotifier` owns the
// player (a second player would drift out of sync) and decides what "play this
// station" means, via the `onPlayStation` callback.
import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart' show ValueChanged;
import 'package:just_audio/just_audio.dart';

import '../models/radio_station.dart';
import '../utils/station_lists.dart';
import 'station_artwork_service.dart';

class RadioAudioHandler extends BaseAudioHandler {
  final AudioPlayer _player;
  final _artworkService = StationArtworkService();

  RadioStation? _station;
  String? _songTitle;
  /// The list skip/queue walk: the selected state's list, or the other state
  /// folder the car last played from.
  List<RadioStation> _browsableStations = const [];

  /// The selected state's list (what its folder shows) and that state's name.
  List<RadioStation> _homeStations = const [];
  String? _homeState;

  /// Other states' lists, fetched when the car opens their folder.
  final _otherStates = <String, List<RadioStation>>{};

  /// Set by `PlayerNotifier`: fetches (sorted, deduped) stations of any state.
  Future<List<RadioStation>> Function(String stateName)? fetchStateStations;

  /// Set by `PlayerNotifier`: called when a station is chosen from Android
  /// Auto or the lock-screen skip buttons.
  ValueChanged<RadioStation>? onPlayStation;

  RadioAudioHandler(AudioPlayer player) : _player = player {
    player.playbackEventStream.listen((_) => _broadcastState());
  }

  /// Re-publishes state and media item without any playback change. iOS can
  /// silently drop the app's Now Playing status while audio keeps playing, and
  /// nothing prompts a re-announcement (see `PlayerNotifier.handleAppResumed`).
  void refreshNowPlayingInfo() {
    _broadcastState();
    unawaited(_rebuildMediaItem());
  }

  /// Mirrors the player into the OS `PlaybackState`. Listening to the player
  /// (not only to calls through this handler) keeps the notification right
  /// when the change came from the app's own UI.
  ///
  /// Skip controls are declared because iOS only enables its remote commands
  /// for declared controls; they switch station, not track (see [_skipStation]).
  void _broadcastState() {
    final playing = _player.playing;
    final station = _station;
    final queueIndex = station == null ? -1 : _indexOf(station);
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
      // Android Auto's Now Playing needs a real queue + index to show skip
      // buttons; `null` (not -1) when the station is not in the list.
      queueIndex: queueIndex < 0 ? null : queueIndex,
    ));
  }

  int _indexOf(RadioStation station) => _browsableStations.indexWhere((s) => s.streamUrl == station.streamUrl);

  /// Sets the notification's station name/genre/logo (and drops the previous
  /// station's song title).
  void setMediaItemForStation(RadioStation station) {
    _station = station;
    _songTitle = null;
    unawaited(_rebuildMediaItem());
  }

  /// Adds the ICY song title to the notification; `null`/empty reverts to the
  /// station name only.
  void updateNowPlayingTitle(String? title) {
    _songTitle = (title == null || title.isEmpty) ? null : title;
    unawaited(_rebuildMediaItem());
  }

  Future<void> _rebuildMediaItem() async {
    final station = _station;
    if (station == null) return;
    final songTitle = _songTitle;
    final artCacheFile = await _resolveArtCacheFile(station);
    // Staleness guard: a slower earlier call must not overwrite a newer one.
    if (_station != station || _songTitle != songTitle) return;
    mediaItem.add(MediaItem(
      id: station.streamUrl,
      // The song takes the headline when known, like a music app.
      title: songTitle ?? station.name,
      artist: songTitle != null ? station.name : station.genre,
      // `audio_service 0.18.19` never fetches `artUri` on either platform; it
      // only reads a local file from `extras['artCacheFile']`, and iOS skips
      // artwork entirely when `artUri` is null — so both point at the same
      // local file (`artUri` is only there to pass iOS's gate).
      artUri: artCacheFile == null ? null : Uri.file(artCacheFile),
      extras: artCacheFile == null ? null : {'artCacheFile': artCacheFile},
    ));
  }

  /// Local file of the station's favicon, or generated initials when it has
  /// none (never a blank square). Null only if even that fails.
  Future<String?> _resolveArtCacheFile(RadioStation station) async {
    try {
      return await _artworkService.cachedArtworkFilePath(station);
    } catch (_) {
      return null;
    }
  }

  /// Browse-list item: the same mapping as the notification, without a song.
  MediaItem _stationToMediaItem(RadioStation station) => MediaItem(
        id: station.streamUrl,
        title: station.name,
        artist: station.genre,
        artUri: station.faviconUrl != null ? Uri.tryParse(station.faviconUrl!) : null,
      );

  /// The selected state's list, shown in its Android Auto folder and used for
  /// skip/queue. Deliberately the *unfiltered* per-state list, not the
  /// Favoritas/Todas view: a passenger or someone at the lock screen cannot see
  /// which tab was selected.
  void updateBrowsableStations(List<RadioStation> stations, {String? stateName}) {
    _homeStations = stations;
    _homeState = stateName ?? _homeState;
    _browsableStations = stations;
    queue.add(stations.map(_stationToMediaItem).toList());
  }

  static const _stateFolderPrefix = 'state:';

  /// Android Auto can't ask a question, so "which state?" is the root: one
  /// folder per state (the person's own first), each listing its stations.
  /// The app's selected state is never changed by browsing here.
  @override
  Future<List<MediaItem>> getChildren(String parentMediaId, [Map<String, dynamic>? options]) async {
    if (parentMediaId == AudioService.browsableRootId) {
      return [
        for (final name in browseStateOrder(_homeState))
          MediaItem(
            id: '$_stateFolderPrefix$name',
            title: name == _homeState ? '$name (seu estado)' : name,
            playable: false,
          ),
      ];
    }
    if (!parentMediaId.startsWith(_stateFolderPrefix)) return const [];
    final name = parentMediaId.substring(_stateFolderPrefix.length);
    if (name == _homeState) return _homeStations.map(_stationToMediaItem).toList();
    var stations = _otherStates[name];
    if (stations == null) {
      try {
        stations = await fetchStateStations?.call(name) ?? const [];
      } catch (_) {
        stations = const [];
      }
      // Empty (offline) is not cached, so the next open retries.
      if (stations.isNotEmpty) _otherStates[name] = stations;
    }
    return stations.map(_stationToMediaItem).toList();
  }

  /// Plays [station] and makes [list] the one skip/queue walk.
  void _playFrom(List<RadioStation> list, RadioStation station) {
    if (!identical(_browsableStations, list)) {
      _browsableStations = list;
      queue.add(list.map(_stationToMediaItem).toList());
    }
    onPlayStation?.call(station);
  }

  /// Every list the car has shown, the selected state's first.
  Iterable<List<RadioStation>> get _knownLists => [_homeStations, ..._otherStates.values];

  /// A station tapped in Android Auto; `mediaId` is the stream URL.
  @override
  Future<void> playFromMediaId(String mediaId, [Map<String, dynamic>? extras]) async {
    for (final list in _knownLists) {
      for (final station in list) {
        if (station.streamUrl == mediaId) return _playFrom(list, station);
      }
    }
  }

  /// Android Auto / Assistant voice search ("toque Antena 1 no Nice Radio"),
  /// across the selected state and any state the car has opened. An empty
  /// query ("toque uma rádio") plays the current station, or the first. No
  /// match does nothing (voice users can't dismiss an error).
  @override
  Future<void> playFromSearch(String query, [Map<String, dynamic>? extras]) async {
    if (query.trim().isEmpty) {
      final station = _station ?? (_homeStations.isEmpty ? null : _homeStations.first);
      if (station != null) _playFrom(_browsableStations, station);
      return;
    }
    for (final list in _knownLists) {
      final station = findStationByQuery(list, query);
      if (station != null) return _playFrom(list, station);
    }
  }

  @override
  Future<void> skipToNext() => _skipStation(1);

  @override
  Future<void> skipToPrevious() => _skipStation(-1);

  /// Lock-screen skip: next/previous station in the browsable list (wraps).
  Future<void> _skipStation(int direction) async {
    final station = _station;
    if (station == null || _browsableStations.isEmpty) return;
    final currentIndex = _indexOf(station);
    if (currentIndex == -1) return;
    final nextIndex = (currentIndex + direction) % _browsableStations.length; // never negative in Dart
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
