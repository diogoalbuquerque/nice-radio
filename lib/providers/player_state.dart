// Immutable snapshot of "what the radio is doing right now", owned by
// `PlayerNotifier`. Favorite status is deliberately NOT here: it lives in
// `favoritesProvider` (keyed by station id) so there is one source of truth.
import '../models/radio_station.dart';

/// Whole minutes left until [endsAt], rounded up (so "1 min" shows until the
/// very end, never "0 min" while time remains); 0 once it has passed.
int remainingSleepMinutes(DateTime endsAt, DateTime now) {
  final seconds = endsAt.difference(now).inSeconds;
  return seconds <= 0 ? 0 : (seconds / 60).ceil();
}

class PlayerState {
  final RadioStation? currentStation;
  final bool isPlaying;
  final bool isLoading;
  final int volumePercent; // 0-100, always a multiple of 10 (see setVolumePercent)
  final int sleepMinutes; // chosen duration; 0 means "no timer set"
  final int sleepRemainingMinutes; // countdown shown on the button; 0 when none

  /// Whether the phone's own speaker is being forced. Recomputed at the start
  /// of every play attempt from what is connected; never a user setting.
  final bool speakerOn;
  final String? nowPlayingTitle;
  final String? errorMessage;

  /// A counter, not a bool: bumped on every 3rd consecutive connection
  /// failure so `ref.listen` sees each occurrence as a new event.
  final int stationsOfflineTrigger;

  const PlayerState({
    required this.currentStation,
    required this.isPlaying,
    required this.isLoading,
    required this.volumePercent,
    required this.sleepMinutes,
    required this.sleepRemainingMinutes,
    required this.speakerOn,
    required this.nowPlayingTitle,
    required this.errorMessage,
    required this.stationsOfflineTrigger,
  });

  const PlayerState.initial()
      : currentStation = null,
        isPlaying = false,
        isLoading = false,
        volumePercent = 60, // placeholder until the real system volume is read
        sleepMinutes = 0,
        sleepRemainingMinutes = 0,
        speakerOn = false,
        nowPlayingTitle = null,
        errorMessage = null,
        stationsOfflineTrigger = 0;

  /// Default for the two nullable fields of [copyWith], so an explicit `null`
  /// (clear the field) differs from omitting it (keep it). Compared with
  /// `identical`. Never rebuild the whole state by hand to clear a field.
  static const Object _unset = Object();

  PlayerState copyWith({
    RadioStation? currentStation,
    bool? isPlaying,
    bool? isLoading,
    int? volumePercent,
    int? sleepMinutes,
    int? sleepRemainingMinutes,
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
      sleepRemainingMinutes: sleepRemainingMinutes ?? this.sleepRemainingMinutes,
      speakerOn: speakerOn ?? this.speakerOn,
      nowPlayingTitle:
          identical(nowPlayingTitle, _unset) ? this.nowPlayingTitle : nowPlayingTitle as String?,
      errorMessage: identical(errorMessage, _unset) ? this.errorMessage : errorMessage as String?,
      stationsOfflineTrigger: stationsOfflineTrigger ?? this.stationsOfflineTrigger,
    );
  }
}
