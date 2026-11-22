import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nice_radio/services/station_list_service.dart';

void main() {
  // The CDN's JSON uses Radio Browser's field names.
  Map<String, Object> entry(String id, String name, {String url = 'https://s.example/live'}) =>
      {'stationuuid': id, 'name': name, 'url': url, 'url_resolved': url, 'favicon': '', 'tags': 'pop', 'state': 'São Paulo', 'bitrate': 128};

  test('asks for the state UF file and keeps accents intact', () async {
    Uri? asked;
    final client = MockClient((request) async {
      asked = request.url;
      // UTF-8 bytes with no charset in the content type, exactly as Cloudflare
      // serves it: `http` would read `response.body` as Latin-1 ("SÃ£o").
      return http.Response.bytes(utf8.encode(jsonEncode([entry('a', 'Rádio São João 98,1 FM')])), 200,
          headers: {'content-type': 'application/json'});
    });

    final stations = await StationListService(client: client).fetchStationsByState('São Paulo');

    expect(asked.toString(), '${StationListService.baseUrl}/SP.json');
    expect(stations.single.name, 'Rádio São João 98,1 FM');
    expect(stations.single.state, 'São Paulo');
  });

  test('drops malformed entries and non-http streams', () async {
    final client = MockClient((_) async => http.Response.bytes(
        utf8.encode(jsonEncode([entry('a', 'Boa'), entry('b', 'Ruim', url: 'javascript:x'), 'lixo', {'name': 'sem id'}])), 200));

    final stations = await StationListService(client: client).fetchStationsByState('São Paulo');

    expect(stations.map((s) => s.id), ['a']);
  });

  test('returns an empty list on HTTP error, bad JSON or network failure', () async {
    for (final client in [
      MockClient((_) async => http.Response('', 404)),
      MockClient((_) async => http.Response('{not json', 200)),
      MockClient((_) async => throw http.ClientException('offline')),
    ]) {
      expect(await StationListService(client: client).fetchStationsByState('Bahia'), isEmpty);
    }
  });

  test('an unknown state name makes no request', () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      return http.Response('[]', 200);
    });

    expect(await StationListService(client: client).fetchStationsByState('Atlântida'), isEmpty);
    expect(calls, 0);
  });
}
