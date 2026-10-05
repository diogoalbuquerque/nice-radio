// Pure list logic: dial sorting, de-duplication, cold-start pick, voice search.
import 'package:flutter_test/flutter_test.dart';
import 'package:nice_radio/models/radio_station.dart';
import 'package:nice_radio/utils/station_lists.dart';

RadioStation _station({required String id, required String name, String? url}) => RadioStation(
      id: id,
      name: name,
      streamUrl: url ?? 'https://example.com/$id',
      faviconUrl: null,
      genre: 'Rádio',
      state: '',
      bitrateKbps: 0,
    );

void main() {
  group('pickInitialStation', () {
    final stations = [
      _station(id: 'a', name: 'Rádio A'),
      _station(id: 'b', name: 'Rádio B'),
    ];

    test('returns the remembered station when it still exists', () {
      expect(pickInitialStation(stations, _station(id: 'b', name: 'old name'))!.name, 'Rádio B');
    });

    test('falls back to the first station when the remembered one is gone', () {
      expect(pickInitialStation(stations, _station(id: 'gone', name: 'X'))!.id, 'a');
    });

    test('falls back to the first station when nothing was remembered', () {
      expect(pickInitialStation(stations, null)!.id, 'a');
    });

    test('returns null for an empty list', () {
      expect(pickInitialStation(const [], _station(id: 'a', name: 'A')), isNull);
    });
  });

  group('findStationByQuery', () {
    final stations = [
      _station(id: '1', name: 'Antena 1 Rock'),
      _station(id: '2', name: 'Antena 1'),
      _station(id: '3', name: '94,7 MHz FM Rádio Pampa'),
      _station(id: '4', name: 'Jovem Pan São Paulo'),
    ];

    test('ignores case, accents and punctuation', () {
      expect(findStationByQuery(stations, 'jovem pan sao paulo')!.id, '4');
      expect(findStationByQuery(stations, 'RADIO PAMPA')!.id, '3');
    });

    test('matches a frequency', () {
      expect(findStationByQuery(stations, '94,7')!.id, '3');
    });

    test('prefers the shortest (most specific) name among matches', () {
      expect(findStationByQuery(stations, 'antena 1')!.id, '2');
    });

    test('returns null when a word is missing or the query is blank', () {
      expect(findStationByQuery(stations, 'antena 2'), isNull);
      expect(findStationByQuery(stations, '   '), isNull);
    });
  });

  group('dedupeStationsByStream', () {
    test('merges the same stream, ignoring query string, scheme and trailing slash', () {
      final result = dedupeStationsByStream([
        _station(id: '1', name: 'Rede 3.16', url: 'https://srv.example.com:7976/live'),
        _station(id: '2', name: 'Rede 3.16', url: 'https://srv.example.com:7976/live?1661877997950'),
        _station(id: '3', name: 'Rede 3.16', url: 'http://SRV.example.com:7976/live/'),
      ]);

      expect(result.map((s) => s.id), ['1']);
    });

    test('keeps channels that share a host but differ by path or port', () {
      final result = dedupeStationsByStream([
        _station(id: '1', name: 'Cidade', url: 'http://stw.example.com/CIDADE.aac'),
        _station(id: '2', name: 'Cidade - drop80', url: 'http://stw.example.com/DROP80.aac'),
        _station(id: '3', name: 'Outra', url: 'http://stw.example.com:8000/CIDADE.aac'),
      ]);

      expect(result.map((s) => s.id), ['1', '2', '3']);
    });

    test('keeps the first entry and preserves order', () {
      final result = dedupeStationsByStream([
        _station(id: 'b', name: 'B', url: 'https://x.example.com/b'),
        _station(id: 'a', name: 'A', url: 'https://x.example.com/a'),
        _station(id: 'b2', name: 'B again', url: 'https://x.example.com/b?x=1'),
      ]);

      expect(result.map((s) => s.id), ['b', 'a']);
    });
  });

  group('sortStationsByFrequency', () {
    test('orders ascending by frequency regardless of input order', () {
      final highest = _station(id: '1', name: 'Rádio C FM 107.5');
      final lowest = _station(id: '2', name: 'Rádio A FM 87.9');
      final middle = _station(id: '3', name: 'Rádio B FM 96.1');

      final sorted = sortStationsByFrequency([highest, lowest, middle]);

      expect(sorted.map((s) => s.id), ['2', '3', '1']);
    });

    test('pushes stations with no detectable frequency to the end, sorted by name', () {
      final noFrequencyZ = _station(id: '1', name: 'Zeta Comunitária');
      final noFrequencyA = _station(id: '2', name: 'Alfa Comunitária');
      final withFrequency = _station(id: '3', name: 'Rádio FM 90.0');

      final sorted = sortStationsByFrequency([noFrequencyZ, withFrequency, noFrequencyA]);

      expect(sorted.map((s) => s.id), ['3', '2', '1']);
    });

    test('does not mutate the original list', () {
      final a = _station(id: '1', name: 'Rádio A FM 100.0');
      final b = _station(id: '2', name: 'Rádio B FM 90.0');
      final original = [a, b];

      sortStationsByFrequency(original);

      expect(original, [a, b]);
    });
  });
}
