// Covers RadioStation's two JSON boundaries — parsing Radio Browser's API
// shape (fromJson) and this app's own cache shape (toJson/fromCache) —
// plus initials, which has a specific real-world bug regression to guard
// (see the comment on RadioStation.initials).
import 'package:flutter_test/flutter_test.dart';
import 'package:nice_radio/models/radio_station.dart';

void main() {
  group('RadioStation.fromJson (Radio Browser API shape)', () {
    test('parses a well-formed entry', () {
      final station = RadioStation.fromJson({
        'stationuuid': 'abc-123',
        'name': 'Antena 1 SP',
        'url_resolved': 'https://stream.example.com/antena1',
        'url': 'http://fallback.example.com/antena1',
        'favicon': 'https://example.com/favicon.png',
        'tags': 'adult contemporary,jazz',
        'state': 'São Paulo',
        'bitrate': 128,
      });

      expect(station, isNotNull);
      expect(station!.id, 'abc-123');
      expect(station.name, 'Antena 1 SP');
      // url_resolved is preferred over the raw url when both are present.
      expect(station.streamUrl, 'https://stream.example.com/antena1');
      expect(station.faviconUrl, 'https://example.com/favicon.png');
      expect(station.genre, 'Adult contemporary');
      expect(station.state, 'São Paulo');
      expect(station.bitrateKbps, 128);
    });

    test('falls back to url when url_resolved is absent', () {
      final station = RadioStation.fromJson({
        'stationuuid': 'abc-123',
        'name': 'Antena 1 SP',
        'url': 'http://fallback.example.com/antena1',
      });

      expect(station!.streamUrl, 'http://fallback.example.com/antena1');
    });

    test('returns null when there is no usable stream URL', () {
      final station = RadioStation.fromJson({
        'stationuuid': 'abc-123',
        'name': 'Antena 1 SP',
      });

      expect(station, isNull);
    });

    test('returns null when there is no station id', () {
      final station = RadioStation.fromJson({
        'name': 'Antena 1 SP',
        'url': 'http://example.com/stream',
      });

      expect(station, isNull);
    });

    test('defaults a missing/blank name instead of leaving it empty', () {
      final station = RadioStation.fromJson({
        'stationuuid': 'abc-123',
        'name': '   ',
        'url': 'http://example.com/stream',
      });

      expect(station!.name, 'Rádio sem nome');
    });

    test('defaults genre to "Rádio" when tags are missing', () {
      final station = RadioStation.fromJson({
        'stationuuid': 'abc-123',
        'name': 'Antena 1 SP',
        'url': 'http://example.com/stream',
      });

      expect(station!.genre, 'Rádio');
    });

    test('rejects a favicon URL with no http(s) scheme', () {
      final station = RadioStation.fromJson({
        'stationuuid': 'abc-123',
        'name': 'Antena 1 SP',
        'url': 'http://example.com/stream',
        'favicon': 'not-a-url',
      });

      expect(station!.faviconUrl, isNull);
    });

    test('rejects the whole entry when neither URL field has an http(s) scheme', () {
      // A malformed/untrusted stream URL is worse than a malformed favicon
      // one — there is no separate fallback avatar for it, and it goes
      // straight into just_audio's setUrl() — so an entry like this is
      // treated as unusable altogether, the same as a missing URL.
      final station = RadioStation.fromJson({
        'stationuuid': 'abc-123',
        'name': 'Antena 1 SP',
        'url_resolved': 'javascript:alert(1)',
        'url': 'file:///etc/passwd',
      });

      expect(station, isNull);
    });
  });

  group('RadioStation.toJson / fromCache (this app\'s own cache shape)', () {
    test('round-trips every field', () {
      const original = RadioStation(
        id: 'abc-123',
        name: 'Antena 1 SP',
        streamUrl: 'https://stream.example.com/antena1',
        faviconUrl: 'https://example.com/favicon.png',
        genre: 'Adult contemporary',
        state: 'São Paulo',
        bitrateKbps: 128,
      );

      final restored = RadioStation.fromCache(original.toJson());

      expect(restored, isNotNull);
      expect(restored!.id, original.id);
      expect(restored.name, original.name);
      expect(restored.streamUrl, original.streamUrl);
      expect(restored.faviconUrl, original.faviconUrl);
      expect(restored.genre, original.genre);
      expect(restored.state, original.state);
      expect(restored.bitrateKbps, original.bitrateKbps);
    });

    test('returns null for a cache entry missing a required field', () {
      final restored = RadioStation.fromCache({'id': 'abc-123'});
      expect(restored, isNull);
    });
  });

  group('RadioStation.initials', () {
    test('takes the first letter of the first and last word', () {
      const station = RadioStation(
        id: '1',
        name: 'Antena 1 SP',
        streamUrl: 'https://example.com',
        faviconUrl: null,
        genre: 'Rádio',
        state: '',
        bitrateKbps: 0,
      );

      expect(station.initials, 'AS');
    });

    test(
      'skips numeric/technical suffixes like "[aac]" — regression for a '
      'real station name that used to produce "A[" instead of a letter',
      () {
        const station = RadioStation(
          id: '1',
          name: 'Antena 1 São Paulo, SP (ZYD823 94,7 MHz FM) [aac]',
          streamUrl: 'https://example.com',
          faviconUrl: null,
          genre: 'Rádio',
          state: '',
          bitrateKbps: 0,
        );

        expect(station.initials, 'AF');
      },
    );

    test('returns a single letter for a one-word name', () {
      const station = RadioStation(
        id: '1',
        name: 'Antena',
        streamUrl: 'https://example.com',
        faviconUrl: null,
        genre: 'Rádio',
        state: '',
        bitrateKbps: 0,
      );

      expect(station.initials, 'A');
    });
  });

  group('RadioStation.avatarColor', () {
    test('is deterministic for the same id', () {
      const a = RadioStation(
        id: 'same-id',
        name: 'Station A',
        streamUrl: 'https://example.com/a',
        faviconUrl: null,
        genre: 'Rádio',
        state: '',
        bitrateKbps: 0,
      );
      const b = RadioStation(
        id: 'same-id',
        name: 'Completely different name',
        streamUrl: 'https://example.com/b',
        faviconUrl: null,
        genre: 'Rádio',
        state: '',
        bitrateKbps: 0,
      );

      expect(a.avatarColor, b.avatarColor);
    });
  });

  group('RadioStation.displayName / frequencySortKey', () {
    test('moves a "number then band" frequency to the front', () {
      const station = RadioStation(
        id: '1',
        name: 'Antena 1 São Paulo, SP (ZYD823 94,7 MHz FM) [aac]',
        streamUrl: 'https://example.com',
        faviconUrl: null,
        genre: 'Rádio',
        state: '',
        bitrateKbps: 0,
      );

      expect(station.displayName, '94,7 FM — Antena 1 São Paulo, SP (ZYD823) [aac]');
      expect(station.frequencySortKey, closeTo(94.7, 0.001));
      // displayName must never affect the avatar — initials still reads
      // the untouched `name`, regression-covered above.
      expect(station.initials, 'AF');
    });

    test('moves a "band then number" frequency to the front', () {
      const station = RadioStation(
        id: '2',
        name: 'Jovem Pan FM 100.9',
        streamUrl: 'https://example.com',
        faviconUrl: null,
        genre: 'Rádio',
        state: '',
        bitrateKbps: 0,
      );

      expect(station.displayName, 'FM 100.9 — Jovem Pan');
      expect(station.frequencySortKey, closeTo(100.9, 0.001));
    });

    test('falls back to the plain name when no frequency is found', () {
      const station = RadioStation(
        id: '3',
        name: 'Rádio Comunitária Sem Frequência',
        streamUrl: 'https://example.com',
        faviconUrl: null,
        genre: 'Rádio',
        state: '',
        bitrateKbps: 0,
      );

      expect(station.displayName, station.name);
      expect(station.frequencySortKey, double.infinity);
    });
  });

  group('RadioStation.listLabel', () {
    RadioStation named(String name) => RadioStation(
          id: '1',
          name: name,
          streamUrl: 'https://example.com',
          faviconUrl: null,
          genre: 'Rádio',
          state: '',
          bitrateKbps: 0,
        );

    test('puts state, then frequency, then the name', () {
      expect(named('Rádio O Dia 98,1 FM').listLabel('RJ'), 'RJ - 98,1 FM - Rádio O Dia');
    });

    test('has no frequency part when none is found', () {
      expect(named('Rádio Comunitária').listLabel('RJ'), 'RJ - Rádio Comunitária');
    });

    test('leaves the state prefix out when unknown', () {
      expect(named('Rádio O Dia 98,1 FM').listLabel(null), '98,1 FM - Rádio O Dia');
    });
  });
}
