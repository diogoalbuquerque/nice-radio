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
import '../utils/station_lists.dart';
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
        case VoiceAction.playStation:
          await _playStation(command);
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

  Future<void> _playStation(VoiceCommand command) async {
    await _ref.read(settingsProvider.future);
    final stations = await _ref.read(stationsProvider.future);
    RadioStation? station;
    final id = command.stationId;
    if (id != null) {
      for (final s in stations) {
        if (s.id == id) station = s;
      }
    }
    final query = command.station;
    if (station == null && query != null) station = findStationByQuery(stations, query);
    if (station != null) await _ref.read(playerProvider.notifier).playStation(station);
  }
}
