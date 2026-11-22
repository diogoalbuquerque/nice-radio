// Downloads the station list for one state from this project's own CDN
// (Cloudflare Pages), built weekly by `.github/workflows/stations.yml` from
// Radio Browser plus the hand edits in `stations/overrides.json` — see
// `stations/README.md`. The JSON keeps Radio Browser's field names, so
// `RadioStation.fromJson` (and its URL validation: this is still a trust
// boundary) parses it unchanged.
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/radio_station.dart';
import '../utils/brazilian_states.dart';

class StationListService {
  /// Baked into every installed app: changing it strands older versions.
  static const baseUrl = 'https://nice-radio-stations.pages.dev/v1';

  static const Duration _timeout = Duration(seconds: 8);

  final http.Client _client;

  StationListService({http.Client? client}) : _client = client ?? http.Client();

  /// The published stations of [stateName] (a `BrazilianStates.all` name),
  /// in Radio Browser's votes order. `const []` on any failure — offline,
  /// CDN down, bad JSON — so callers fall back calmly instead of crashing.
  Future<List<RadioStation>> fetchStationsByState(String stateName) async {
    final uf = BrazilianStates.abbreviationOf(stateName);
    if (uf == null) return const [];
    try {
      final response = await _client.get(Uri.parse('$baseUrl/$uf.json')).timeout(_timeout);
      if (response.statusCode != 200) return const [];
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(RadioStation.fromJson)
          .whereType<RadioStation>() // drops malformed entries
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
