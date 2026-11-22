// The initials path renders with dart:ui (works under `flutter test`); the
// logo download uses a fake HTTP client and a real temp folder.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nice_radio/models/radio_station.dart';
import 'package:nice_radio/services/station_artwork_service.dart';

const _png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

RadioStation _station({String? faviconUrl}) => RadioStation(
      id: 'abc-123',
      name: 'Antena 1 SP',
      streamUrl: 'https://stream.example.com/antena1',
      faviconUrl: faviconUrl,
      genre: 'Rádio',
      state: 'São Paulo',
      bitrateKbps: 128,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('artwork_test'));
  tearDown(() => dir.delete(recursive: true));

  test('logoBytes renders a real PNG for a station with no favicon', () async {
    final bytes = await StationArtworkService(cacheDir: () async => dir).logoBytes(_station());

    expect(bytes, isNotNull);
    expect(bytes!.sublist(0, 8), equals(_png)); // PNG magic number
  });

  test('cachedLogoFile downloads a logo once and reuses the file', () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      return http.Response.bytes([1, 2, 3], 200);
    });
    final service = StationArtworkService(client: client, cacheDir: () async => dir);
    const url = 'https://cdn.example/v1/logos/abc-123-0123456789.png';

    final first = await service.cachedLogoFile(url);
    final second = await service.cachedLogoFile(url);

    expect(calls, 1);
    expect(second!.path, first!.path);
    expect(await second.readAsBytes(), [1, 2, 3]);
  });

  test('a changed logo URL is downloaded again', () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      return http.Response.bytes([calls], 200);
    });
    final service = StationArtworkService(client: client, cacheDir: () async => dir);

    await service.cachedLogoFile('https://cdn.example/v1/logos/abc-123-aaaaaaaaaa.png');
    final updated = await service.cachedLogoFile('https://cdn.example/v1/logos/abc-123-bbbbbbbbbb.png');

    expect(await updated!.readAsBytes(), [2]);
  });

  test('a failed download is not cached and falls back to initials', () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      return http.Response('', 404);
    });
    final service = StationArtworkService(client: client, cacheDir: () async => dir);
    final station = _station(faviconUrl: 'https://cdn.example/v1/logos/abc-123-0123456789.png');

    expect(await service.cachedLogoFile(station.faviconUrl), isNull);
    expect(await service.cachedLogoFile(station.faviconUrl), isNull);
    expect(calls, 2); // retried, not remembered as missing
    expect((await service.logoBytes(station))!.sublist(0, 8), equals(_png));
    expect(await service.cachedArtworkFilePath(station), contains('station_initials_'));
  });
}
