import 'package:flutter_test/flutter_test.dart';
import 'package:nice_radio/models/radio_station.dart';
import 'package:nice_radio/services/listening_tracker.dart';

RadioStation _station(String id) => RadioStation(
      id: id,
      name: 'Rádio $id',
      streamUrl: 'https://example.com/$id',
      faviconUrl: null,
      genre: 'Rádio',
      state: '',
      bitrateKbps: 0,
    );

void main() {
  late List<(String, int)> sessions;
  late ListeningTracker tracker;

  setUp(() {
    sessions = [];
    tracker = ListeningTracker((station, seconds) => sessions.add((station.id, seconds)));
  });

  test('accumulates ticks and reports one session when playback stops', () {
    tracker.tick(_station('a'), 5);
    tracker.tick(_station('a'), 5);
    expect(sessions, isEmpty);

    tracker.tick(null, 5);
    expect(sessions, [('a', 10)]);
  });

  test('a station switch closes the previous session and starts a new one', () {
    tracker.tick(_station('a'), 5);
    tracker.tick(_station('b'), 5);
    expect(sessions, [('a', 5)]);

    tracker.flush();
    expect(sessions, [('a', 5), ('b', 5)]);
  });

  test('reports nothing when nothing was listened to, and never twice', () {
    tracker.tick(null, 5);
    tracker.flush();
    expect(sessions, isEmpty);

    tracker.tick(_station('a'), 5);
    tracker.flush();
    tracker.flush();
    expect(sessions, [('a', 5)]);
  });
}
