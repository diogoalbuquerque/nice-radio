// Bridge to the native side that receives Siri / Shortcuts (iOS) and
// launcher-shortcut / Google Assistant (Android) requests.
//
// WHY "pull pending commands" instead of the native side pushing each
// command with its payload: when a shortcut launches the app from fully
// closed, the native side has the command *before* Dart has registered
// any handler, so a pushed call would be lost. Native therefore queues
// every command and only pings `commandAvailable`; Dart answers by
// calling `takePendingCommands`, both once at startup and on each ping.
// Same reasoning for the guards as `HomeWidgetService`/`QuickActionsService`.
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

import '../models/radio_station.dart';
import '../models/voice_command.dart';

class VoiceCommandService {
  static const _channel = MethodChannel('com.nice.radio/commands');

  /// Registers [onCommand] and immediately delivers anything queued before
  /// Dart was ready (the command that launched the app).
  Future<void> initialize(Future<void> Function(VoiceCommand command) onCommand) async {
    if (kIsWeb) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'commandAvailable') await _drain(onCommand);
    });
    await _drain(onCommand);
  }

  Future<void> _drain(Future<void> Function(VoiceCommand command) onCommand) async {
    try {
      final pending = await _channel.invokeMethod<List<Object?>>('takePendingCommands') ?? const [];
      for (final raw in pending) {
        if (raw is! Map) continue;
        final command = VoiceCommand.fromMap(raw);
        if (command != null) await onCommand(command);
      }
    } catch (_) {
      // No native command support on this platform/environment.
    }
  }

  /// iOS only: gives Siri/Shortcuts the current state's stations, labeled
  /// like "RJ - 98,1 FM - O Dia" (see [RadioStation.listLabel]) so a long
  /// list is easy to scan, in the order given (dial order). Android answers
  /// "not implemented", which is swallowed.
  Future<void> cacheStations(List<RadioStation> stations, {String? stateAbbreviation}) async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod('cacheStations', [
        for (final s in stations) {'id': s.id, 'name': s.listLabel(stateAbbreviation)},
      ]);
    } catch (_) {
      // Not supported here.
    }
  }
}
