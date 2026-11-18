import 'package:flutter_test/flutter_test.dart';
import 'package:nice_radio/models/radio_station.dart';
import 'package:nice_radio/utils/station_lists.dart';

RadioStation _s(String id) =>
    RadioStation(id: id, name: id, streamUrl: 'http://x/$id', faviconUrl: null, genre: 'Rádio', state: 'RJ', bitrateKbps: 0);

void main() {
  final x = _s('x'), y = _s('y'), z = _s('z');

  test('empty tab has no station', () {
    expect(stationForTab([], rememberedId: 'x', current: z), isNull);
  });

  test('current station not in the tab -> first of the tab', () {
    expect(stationForTab([x, y], rememberedId: null, current: z), x);
  });

  test('current station in the tab is kept', () {
    expect(stationForTab([x, y], rememberedId: null, current: y), y);
  });

  test('remembered station wins over the current one', () {
    expect(stationForTab([x, y, z], rememberedId: 'x', current: z), x);
  });

  test('remembered station no longer in the tab is ignored', () {
    expect(stationForTab([y], rememberedId: 'x', current: z), y);
  });
}
