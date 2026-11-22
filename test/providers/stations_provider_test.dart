import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nice_radio/models/radio_station.dart';
import 'package:nice_radio/providers/settings_provider.dart';
import 'package:nice_radio/providers/stations_provider.dart';
import 'package:nice_radio/services/station_list_service.dart';
import 'package:nice_radio/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeStationListService extends StationListService {
  final List<RadioStation> result;
  _FakeStationListService(this.result);

  @override
  Future<List<RadioStation>> fetchStationsByState(String stateName) async => result;
}

RadioStation _station(String id, String name) => RadioStation(
    id: id, name: name, streamUrl: 'https://s.example/$id', faviconUrl: null, genre: 'Rádio', state: 'Bahia', bitrateKbps: 0);

Future<List<RadioStation>> _stations(List<RadioStation> fetched) async {
  final container = ProviderContainer(overrides: [
    stationListServiceProvider.overrideWithValue(_FakeStationListService(fetched)),
  ]);
  addTearDown(container.dispose);
  await container.read(settingsProvider.future); // the selected state is read from storage first
  return container.read(stationsProvider.future);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({'selected_state': 'Bahia'}));

  test('uses the freshly downloaded list', () async {
    expect((await _stations([_station('a', 'Nova 98,1 FM')])).map((s) => s.id), ['a']);
  });

  test('falls back to the list saved on the device when the CDN fails', () async {
    await StorageService().setBrowsableStations('Bahia', [_station('saved', 'Salva 90,1 FM')]);

    expect((await _stations(const [])).map((s) => s.id), ['saved']);
  });

  test('never uses a list saved for another state', () async {
    await StorageService().setBrowsableStations('Acre', [_station('acre', 'Acre 90,1 FM')]);

    expect(await _stations(const []), isEmpty);
  });
}
