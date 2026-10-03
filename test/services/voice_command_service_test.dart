// With no native side registered (as in `flutter test`), every call must
// quietly do nothing — same contract as QuickActionsService/HomeWidgetService.
// Also checks the pull protocol end to end through a fake native channel.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nice_radio/models/radio_station.dart';
import 'package:nice_radio/models/voice_command.dart';
import 'package:nice_radio/services/voice_command_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.nice.radio/commands');

  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

  test('initialize and cacheStations do not throw without a native side', () async {
    final service = VoiceCommandService();
    await service.initialize((_) async {});
    await service.cacheStations(const []);
  });

  test('initialize delivers queued commands and skips malformed ones', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'takePendingCommands') {
        return [
          {'uri': 'niceradio://pause'},
          {'action': 'bogus'},
          {'action': 'playStation', 'stationId': 'x1'},
        ];
      }
      return null;
    });

    final received = <VoiceCommand>[];
    await VoiceCommandService().initialize((c) async => received.add(c));

    expect(received.map((c) => c.action), [VoiceAction.pause, VoiceAction.playStation]);
    expect(received.last.stationId, 'x1');
  });

  test('cacheStations sends id and a "UF - frequency - name" label', () async {
    Object? sent;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'cacheStations') sent = call.arguments;
      return null;
    });

    await VoiceCommandService().cacheStations([
      const RadioStation(id: 'x', name: 'FM 94,7 Pampa', streamUrl: 'https://e.com/x', faviconUrl: null, genre: 'Rádio', state: '', bitrateKbps: 0),
    ], stateAbbreviation: 'RS');

    expect(sent, [
      {'id': 'x', 'name': 'RS - FM 94,7 - Pampa'},
    ]);
  });
}
