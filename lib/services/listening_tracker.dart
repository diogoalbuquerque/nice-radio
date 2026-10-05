// Turns "is a station playing right now?" ticks into one `listening_session`
// per uninterrupted stretch on one station. Pure logic (no timers, no
// Firebase) so it is unit-testable; `PlayerNotifier` feeds it on its 5s tick
// and passes `AnalyticsService.logListeningSession` as the callback.
import '../models/radio_station.dart';

class ListeningTracker {
  final void Function(RadioStation station, int seconds) _onSession;
  RadioStation? _station;
  int _seconds = 0;

  ListeningTracker(this._onSession);

  /// [playing] is the station being heard right now, or `null` when nothing is
  /// playing. Not playing ends the session; a different station ends the
  /// previous one and starts a new one.
  void tick(RadioStation? playing, int seconds) {
    if (playing == null) {
      flush();
      return;
    }
    if (_station != null && _station!.id != playing.id) flush();
    _station = playing;
    _seconds += seconds;
  }

  /// Reports and resets the current session, if it has any time in it.
  void flush() {
    final station = _station;
    final seconds = _seconds;
    _station = null;
    _seconds = 0;
    if (station == null || seconds <= 0) return;
    _onSession(station, seconds);
  }
}
