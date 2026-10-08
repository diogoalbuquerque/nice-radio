// StorageService is the one place every SharedPreferences key in this app
// lives (see the WHY comment at the top of the source file) — these
// tests exercise every read/write pair through the real SharedPreferences
// test backend (SharedPreferences.setMockInitialValues), not a hand
// rolled fake, so a typo'd key would show up here as a round-trip
// failure.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nice_radio/models/radio_station.dart';
import 'package:nice_radio/services/storage_service.dart';

void main() {
  late StorageService storage;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    storage = StorageService();
  });

  group('favorites', () {
    test('starts empty', () async {
      expect(await storage.getFavoriteIds(), isEmpty);
    });

    test('round-trips a set of ids', () async {
      await storage.setFavoriteIds({'a', 'b', 'c'});
      expect(await storage.getFavoriteIds(), {'a', 'b', 'c'});
    });
  });

  group('selected state', () {
    test('starts unset', () async {
      expect(await storage.getSelectedState(), isNull);
    });

    test('round-trips', () async {
      await storage.setSelectedState('São Paulo');
      expect(await storage.getSelectedState(), 'São Paulo');
    });
  });

  group('data usage', () {
    test('bytes default to zero', () async {
      expect(await storage.getDataUsedBytes(), 0);
    });

    test('round-trips bytes', () async {
      await storage.setDataUsedBytes(123456);
      expect(await storage.getDataUsedBytes(), 123456);
    });

    test('round-trips the "since" date', () async {
      final date = DateTime(2026, 3, 1, 12);
      await storage.setDataUsedSince(date);
      expect(await storage.getDataUsedSince(), date);
    });
  });

  group('dark mode', () {
    test('defaults to false (light mode)', () async {
      expect(await storage.getDarkModeEnabled(), isFalse);
    });

    test('round-trips', () async {
      await storage.setDarkModeEnabled(true);
      expect(await storage.getDarkModeEnabled(), isTrue);

      await storage.setDarkModeEnabled(false);
      expect(await storage.getDarkModeEnabled(), isFalse);
    });
  });

  group('suppress offline warning', () {
    test('defaults to false (dialog is allowed to show)', () async {
      expect(await storage.getSuppressOfflineWarning(), isFalse);
    });

    test('round-trips', () async {
      await storage.setSuppressOfflineWarning(true);
      expect(await storage.getSuppressOfflineWarning(), isTrue);

      await storage.setSuppressOfflineWarning(false);
      expect(await storage.getSuppressOfflineWarning(), isFalse);
    });
  });

  group('view mode (Favoritas/Todas)', () {
    test('defaults to false (Todas)', () async {
      expect(await storage.getViewModeIsFavorites(), isFalse);
    });

    test('round-trips', () async {
      await storage.setViewModeIsFavorites(true);
      expect(await storage.getViewModeIsFavorites(), isTrue);

      await storage.setViewModeIsFavorites(false);
      expect(await storage.getViewModeIsFavorites(), isFalse);
    });
  });

  group('onboarding flag', () {
    test('defaults to false', () async {
      expect(await storage.getOnboardingDone(), isFalse);
    });

    test('round-trips', () async {
      await storage.setOnboardingDone(true);
      expect(await storage.getOnboardingDone(), isTrue);
    });
  });

  group('browsable stations (Android Auto / lock-screen list)', () {
    RadioStation station(String id) => RadioStation(
          id: id,
          name: 'Rádio $id',
          streamUrl: 'https://example.com/$id',
          faviconUrl: null,
          genre: 'Rádio',
          state: 'Rio de Janeiro',
          bitrateKbps: 64,
        );

    test('nothing saved reads as null', () async {
      expect(await storage.getBrowsableStations('Rio de Janeiro'), isNull);
    });

    test('round-trips the list in order for the same state', () async {
      await storage.setBrowsableStations('Rio de Janeiro', [station('b'), station('a')]);

      final restored = await storage.getBrowsableStations('Rio de Janeiro');

      expect(restored!.map((s) => s.id), ['b', 'a']);
      expect(restored.first.streamUrl, 'https://example.com/b');
    });

    test('never returns the list saved for another state', () async {
      await storage.setBrowsableStations('Rio de Janeiro', [station('a')]);

      expect(await storage.getBrowsableStations('São Paulo'), isNull);
    });

    test('a newer save replaces the older one', () async {
      await storage.setBrowsableStations('Rio de Janeiro', [station('a')]);
      await storage.setBrowsableStations('São Paulo', [station('z')]);

      expect(await storage.getBrowsableStations('Rio de Janeiro'), isNull);
      expect((await storage.getBrowsableStations('São Paulo'))!.single.id, 'z');
    });

    test('corrupt stored data reads as null instead of throwing', () async {
      SharedPreferences.setMockInitialValues({'browsable_stations_json': '{not json'});

      expect(await storage.getBrowsableStations('Rio de Janeiro'), isNull);
    });

    test('skips unusable entries and returns null if none survive', () async {
      SharedPreferences.setMockInitialValues({
        'browsable_stations_json':
            '{"state":"Rio de Janeiro","stations":[{"id":"a"},{"id":"b","name":"B","streamUrl":"https://e.com/b"}]}',
      });
      expect((await storage.getBrowsableStations('Rio de Janeiro'))!.map((s) => s.id), ['b']);

      SharedPreferences.setMockInitialValues({
        'browsable_stations_json': '{"state":"Rio de Janeiro","stations":[{"id":"a"}]}',
      });
      expect(await storage.getBrowsableStations('Rio de Janeiro'), isNull);
    });
  });

  group('last station', () {
    const station = RadioStation(
      id: 'abc-123',
      name: 'Antena 1 SP',
      streamUrl: 'https://stream.example.com/antena1',
      faviconUrl: 'https://example.com/favicon.png',
      genre: 'Adult contemporary',
      state: 'São Paulo',
      bitrateKbps: 128,
    );

    test('starts unset', () async {
      expect(await storage.getLastStation(), isNull);
    });

    test('round-trips a station', () async {
      await storage.setLastStation(station);
      final restored = await storage.getLastStation();

      expect(restored, isNotNull);
      expect(restored!.id, station.id);
      expect(restored.name, station.name);
      expect(restored.streamUrl, station.streamUrl);
    });

    test('a later save replaces the earlier one, not merges with it', () async {
      await storage.setLastStation(station);
      const other = RadioStation(
        id: 'xyz-789',
        name: 'Jovem Pan FM',
        streamUrl: 'https://stream.example.com/jovempan',
        faviconUrl: null,
        genre: 'Pop',
        state: 'São Paulo',
        bitrateKbps: 96,
      );
      await storage.setLastStation(other);

      expect((await storage.getLastStation())!.id, 'xyz-789');
    });

    test('a corrupt cache entry is treated as "nothing saved" rather than throwing', () async {
      SharedPreferences.setMockInitialValues({'last_station_json': 'not valid json'});
      storage = StorageService();

      expect(await storage.getLastStation(), isNull);
    });
  });
}
