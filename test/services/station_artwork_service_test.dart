// Only the initials-rendering path is tested here (a station with no
// faviconUrl) — the favicon-fetch path needs a real network call and the
// `artworkUri` path needs a real path_provider platform channel, neither
// of which this test touches, mirroring radio_browser_service_test's
// absence for the same "no fake to substitute" reason. Rendering with dart:ui works fine
// under `flutter test`'s own Skia-backed test binding, no platform
// channel involved, so this part is genuinely testable.
import 'package:flutter_test/flutter_test.dart';
import 'package:nice_radio/models/radio_station.dart';
import 'package:nice_radio/services/station_artwork_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('logoBytes renders a real PNG for a station with no favicon', () async {
    const station = RadioStation(
      id: 'abc-123',
      name: 'Antena 1 SP',
      streamUrl: 'https://stream.example.com/antena1',
      faviconUrl: null,
      genre: 'Rádio',
      state: 'São Paulo',
      bitrateKbps: 128,
    );

    final bytes = await StationArtworkService().logoBytes(station);

    expect(bytes, isNotNull);
    expect(bytes!.length, greaterThan(0));
    // PNG magic number: every PNG file starts with these 8 bytes.
    expect(bytes.sublist(0, 8), equals([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]));
  });
}
