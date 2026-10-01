// Same reasoning as system_volume_service_test.dart: no home-screen
// shortcut platform channel is registered in a plain `flutter test` run,
// so these tests exist to pin down that every call degrades quietly
// instead of throwing.
import 'package:flutter_test/flutter_test.dart';
import 'package:nice_radio/models/radio_station.dart';
import 'package:nice_radio/services/quick_actions_service.dart';

void main() {
  // See system_volume_service_test.dart's identical setup line for why:
  // platform-channel code needs the test binding initialized first.
  TestWidgetsFlutterBinding.ensureInitialized();

  late QuickActionsService service;

  setUp(() {
    service = QuickActionsService();
  });

  test('initialize does not throw', () async {
    await expectLater(service.initialize(() async {}), completes);
  });

  test('updateShortcut does not throw when given a station', () async {
    const station = RadioStation(
      id: 'abc-123',
      name: 'Antena 1 SP',
      streamUrl: 'https://stream.example.com/antena1',
      faviconUrl: null,
      genre: 'Rádio',
      state: 'São Paulo',
      bitrateKbps: 128,
    );

    await expectLater(service.updateShortcut(station), completes);
  });

  test('updateShortcut does not throw when clearing (station is null)', () async {
    await expectLater(service.updateShortcut(null), completes);
  });
}
