// Talks to the Radio Browser API (https://api.radio-browser.info) — a
// free, open, community-maintained directory of internet radio streams
// that (unlike scraping a station-listing website) exposes a real `state`
// field per station, which is exactly what lets us filter to "only radios
// from the user's state" reliably.
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/radio_station.dart';

class RadioBrowserService {
  /// Radio Browser is mirrored across several independently-run servers.
  /// The "correct" way to discover one is an SRV DNS lookup against
  /// `_api._tcp.radio-browser.info`, but Dart's `http` package has no
  /// built-in SRV support and adding a DNS package just for this would be
  /// a lot of machinery for a hobby project. Instead we keep a short list
  /// of known mirrors and fail over to the next one on error — simpler,
  /// and resilient enough for a client that only reads data.
  static const List<String> _mirrorHosts = [
    'de1.api.radio-browser.info',
    'de2.api.radio-browser.info',
    'at1.api.radio-browser.info',
  ];

  static const Duration _timeout = Duration(seconds: 8);

  /// Radio Browser's usage guidelines ask clients to identify themselves
  /// with a distinctive User-Agent (rather than a generic Dart/http one)
  /// so mirror operators can see real app traffic vs. abuse. This is a
  /// courtesy to a free community service, not a technical requirement.
  static const String _userAgent = 'NiceRadio/1.0 (+https://github.com)';

  /// Fetches stations for one Brazilian state, most-voted first (voting
  /// is Radio Browser's crowd-sourced signal for "this stream actually
  /// works"), so the elderly user is less likely to tap into a dead
  /// stream on their first try.
  ///
  /// [stateName] must be one of [BrazilianStates.all]'s canonical names —
  /// Radio Browser matches it as case-insensitive free text against its
  /// own `state` field.
  Future<List<RadioStation>> fetchStationsByState(
    String stateName, {
    int limit = 100,
  }) async {
    for (final host in _mirrorHosts) {
      try {
        final uri = Uri.https(host, '/json/stations/search', {
          'country': 'Brazil',
          'state': stateName,
          'limit': '$limit',
          'order': 'votes',
          'reverse': 'true',
          // Radio Browser flags streams its own health-checker has found
          // to be down; hiding those spares the user a "why won't this
          // play" moment on a station that is known to be dead.
          'hidebroken': 'true',
        });

        final response = await http
            .get(uri, headers: const {'User-Agent': _userAgent})
            .timeout(_timeout);

        if (response.statusCode != 200) continue;

        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is! List) continue;

        return decoded
            .whereType<Map<String, dynamic>>()
            .map(RadioStation.fromJson)
            .whereType<RadioStation>() // drops the nulls from malformed entries
            .toList();
      } on SocketException {
        continue; // this mirror is unreachable — try the next one
      } on http.ClientException {
        continue;
      } catch (_) {
        continue; // malformed JSON or anything else unexpected from this mirror
      }
    }

    // Every mirror failed (or the device is offline). Returning an empty
    // list — rather than throwing — lets the UI show a calm "no stations
    // found, check your connection" state instead of a crash screen,
    // which matters a lot more for this audience than for a typical app.
    return const [];
  }
}
