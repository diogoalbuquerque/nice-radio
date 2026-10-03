// VoiceCommand is the single shape both platforms' shortcut/Siri/Assistant
// requests are translated into, so a parsing slip here silently breaks
// voice control on one platform. Covers the Android URI form, the iOS map
// form, and that garbage is ignored rather than throwing.
import 'package:flutter_test/flutter_test.dart';
import 'package:nice_radio/models/voice_command.dart';

void main() {
  group('VoiceCommand.fromUri (Android)', () {
    test('parses the simple actions', () {
      expect(VoiceCommand.fromUri('niceradio://play')!.action, VoiceAction.play);
      expect(VoiceCommand.fromUri('niceradio://pause')!.action, VoiceAction.pause);
      expect(VoiceCommand.fromUri('niceradio://next')!.action, VoiceAction.next);
      expect(VoiceCommand.fromUri('niceradio://previous')!.action, VoiceAction.previous);
    });

    test('resolves the state name to its canonical spelling', () {
      final command = VoiceCommand.fromUri('niceradio://playstate?name=sao%20paulo')!;
      expect(command.action, VoiceAction.playState);
      expect(command.state, 'São Paulo');
    });

    test('parses a station query', () {
      final command = VoiceCommand.fromUri('niceradio://station?name=Antena%201')!;
      expect(command.action, VoiceAction.playStation);
      expect(command.station, 'Antena 1');
    });

    test('unwraps the Assistant "open app feature" form', () {
      expect(VoiceCommand.fromUri('niceradio://feature?featureName=pause')!.action, VoiceAction.pause);
    });

    test('ignores other schemes, unknown actions, unknown states and empty queries', () {
      expect(VoiceCommand.fromUri('https://example.com/play'), isNull);
      expect(VoiceCommand.fromUri('niceradio://explode'), isNull);
      expect(VoiceCommand.fromUri('niceradio://state?name=Atlantida'), isNull);
      expect(VoiceCommand.fromUri('niceradio://station?name=%20'), isNull);
    });
  });

  group('VoiceCommand.fromMap', () {
    test('reads the Android uri form', () {
      expect(VoiceCommand.fromMap({'uri': 'niceradio://next'})!.action, VoiceAction.next);
    });

    test('reads the iOS action form', () {
      final command = VoiceCommand.fromMap({'action': 'chooseState', 'state': 'Bahia'})!;
      expect(command.action, VoiceAction.chooseState);
      expect(command.state, 'Bahia');

      final station = VoiceCommand.fromMap({'action': 'playStation', 'station': '94,7 FM Rádio X'})!;
      expect(station.station, '94,7 FM Rádio X');
    });

    test('returns null for an empty or unknown map', () {
      expect(VoiceCommand.fromMap({}), isNull);
      expect(VoiceCommand.fromMap({'action': 'nope'}), isNull);
    });
  });
}
