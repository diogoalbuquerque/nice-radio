// Same reasoning as quick_actions_service_test.dart/
// system_volume_service_test.dart: no home-screen-widget platform channel
// is registered in a plain `flutter test` run, so these tests exist to pin
// down that every call degrades quietly instead of throwing.
import 'package:flutter_test/flutter_test.dart';
import 'package:nice_radio/services/home_widget_service.dart';

void main() {
  // See system_volume_service_test.dart's identical setup line for why:
  // platform-channel code needs the test binding initialized first.
  TestWidgetsFlutterBinding.ensureInitialized();

  late HomeWidgetService service;

  setUp(() {
    service = HomeWidgetService();
  });

  test('updateNowPlaying does not throw with no song title', () async {
    await expectLater(
      service.updateNowPlaying(stationName: 'Antena 1 SP', songTitle: null, isPlaying: true),
      completes,
    );
  });

  test('updateNowPlaying does not throw with a song title', () async {
    await expectLater(
      service.updateNowPlaying(stationName: 'Antena 1 SP', songTitle: 'Some Song', isPlaying: false),
      completes,
    );
  });

  test('setActionHandler does not throw', () {
    expect(() => service.setActionHandler((_) async {}), returnsNormally);
  });
}
