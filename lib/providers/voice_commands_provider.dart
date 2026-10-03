// Decides what each outside request (Siri, Shortcuts, launcher shortcut,
// Google Assistant — all already translated to a `VoiceCommand`) actually
// does. Lives here, not in `main.dart`, so every platform entry point shares
// one behavior and it stays readable in one place.
//
// Design rule: a command either does what was asked or does nothing — it
// never throws and never leaves the app in a half-changed state. People
// using voice control cannot see or fix an error dialog.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/radio_station.dart';
import '../models/voice_command.dart';
import 'player_provider.dart';
import 'settings_provider.dart';
import 'stations_provider.dart';

final voiceCommandHandlerProvider = Provider<VoiceCommandHandler>(VoiceCommandHandler.new);

class VoiceCommandHandler {
  final Ref _ref;

  VoiceCommandHandler(this._ref);

  Future<void> handle(VoiceCommand command) async {
    try {
      switch (command.action) {
        case VoiceAction.play:
          await _play();
        case VoiceAction.pause:
          final player = _ref.read(playerProvider);
          if (player.isPlaying || player.isLoading) {
            await _ref.read(playerProvider.notifier).togglePlayPause();
          }
        case VoiceAction.next:
          if (_ref.read(playerProvider).currentStation != null) {
            await _ref.read(playerProvider.notifier).playNext();
          }
        case VoiceAction.previous:
          if (_ref.read(playerProvider).currentStation != null) {
            await _ref.read(playerProvider.notifier).playPrevious();
          }
        case VoiceAction.chooseState:
          await _selectState(command.state);
        case VoiceAction.playState:
          if (await _selectState(command.state)) await _playStateStation();
        case VoiceAction.playStation:
          await _playStationNamed(command.station);
      }
    } catch (_) {
      // See the design rule in the file header.
    }
  }

  /// Resumes what the person was last listening to; on a brand-new install
  /// (nothing ever played) falls back to the first station of their state.
  Future<void> _play() async {
    final player = _ref.read(playerProvider);
    if (player.isPlaying || player.isLoading) return;
    final notifier = _ref.read(playerProvider.notifier);
    if (player.currentStation != null) return notifier.playFromQuickAction();
    await _ref.read(settingsProvider.future);
    final stations = await _ref.read(stationsProvider.future);
    final station = pickInitialStation(stations, await _ref.read(storageServiceProvider).getLastStation());
    if (station != null) await notifier.playStation(station);
  }

  /// Returns true when the state is now selected (already was, or switched).
  Future<bool> _selectState(String? stateName) async {
    if (stateName == null) return false;
    final settings = await _ref.read(settingsProvider.future);
    if (settings.selectedState != stateName) {
      await _ref.read(settingsProvider.notifier).selectState(stateName);
      // A stale error banner belongs to the previous state's station — the
      // same reason SettingsScreen clears it on a manual pick.
      _ref.read(playerProvider.notifier).clearError();
    }
    return true;
  }

  /// Plays the station of the (just selected) state: the one the person
  /// last had if it belongs to this state, otherwise the first.
  Future<void> _playStateStation() async {
    final stations = await _ref.read(stationsProvider.future);
    final remembered = _ref.read(playerProvider).currentStation ?? await _ref.read(storageServiceProvider).getLastStation();
    final station = pickInitialStation(stations, remembered);
    if (station != null) await _ref.read(playerProvider.notifier).playStation(station);
  }

  Future<void> _playStationNamed(String? query) async {
    if (query == null) return;
    await _ref.read(settingsProvider.future);
    final stations = await _ref.read(stationsProvider.future);
    final RadioStation? station = findStationByQuery(stations, query);
    if (station != null) await _ref.read(playerProvider.notifier).playStation(station);
  }
}
