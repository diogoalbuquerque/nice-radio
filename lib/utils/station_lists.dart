// Pure functions over a `List<RadioStation>`: dial ordering, de-duplication,
// the cold-start pick and voice search. No providers or I/O, so they are
// unit-tested directly (`test/utils/station_lists_test.dart`).
import '../models/radio_station.dart';

/// Orders [stations] like a real radio dial — ascending by
/// [RadioStation.frequencySortKey] — instead of leaving them in Radio
/// Browser's raw votes-ranked order ([RadioBrowserService.fetchStationsByState]
/// still requests `order: votes` from the API itself, since that is still
/// what the server uses to rank/filter results; this is a client-side
/// re-sort layered on top of whatever comes back). Stations with no
/// detectable frequency sort after every station that has one, ordered
/// alphabetically among themselves, so the result is always fully
/// deterministic. Pulled out as its own top-level function — rather than
/// inlined in [stationsProvider] below — so it can be unit tested
/// directly, with no `ProviderContainer` or network call needed; see
/// `stations_provider_test.dart`.
List<RadioStation> sortStationsByFrequency(List<RadioStation> stations) {
  final sorted = [...stations];
  sorted.sort((a, b) {
    final byFrequency = a.frequencySortKey.compareTo(b.frequencySortKey);
    if (byFrequency != 0) return byFrequency;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return sorted;
}

/// Which station the home screen should pre-select on a cold start: the one
/// the person was on when they last closed the app ([saved]) if it is still
/// in [stations] (matched by id, and returning the *list's* copy so a
/// changed stream URL or logo is picked up), otherwise the first entry.
/// Pulled out as a top-level function, like [sortStationsByFrequency], so
/// it can be unit tested with no `ProviderContainer`. Returns null only for
/// an empty list.
RadioStation? pickInitialStation(List<RadioStation> stations, RadioStation? saved) {
  if (stations.isEmpty) return null;
  if (saved != null) {
    for (final station in stations) {
      if (station.id == saved.id) return station;
    }
  }
  return stations.first;
}

/// Finds the station a person asked for by voice or Shortcuts text, e.g.
/// "Antena 1", "rock" or "94,7". Case, accents and punctuation are ignored;
/// every word of [query] must appear in the station's display name or name.
/// Among several matches the shortest name wins (the most specific:
/// "Antena 1" over "Antena 1 Rock"), ties keeping list order.
RadioStation? findStationByQuery(List<RadioStation> stations, String query) {
  final words = _searchWords(query);
  if (words.isEmpty) return null;
  RadioStation? best;
  var bestLength = 1 << 30;
  for (final station in stations) {
    final haystack = _searchWords('${station.displayName} ${station.name}').toSet();
    if (words.every(haystack.contains) && station.name.length < bestLength) {
      best = station;
      bestLength = station.name.length;
    }
  }
  return best;
}

List<String> _searchWords(String text) {
  const from = 'àáâãäçèéêëìíîïñòóôõöùúûü';
  const to = 'aaaaaceeeeiiiinooooouuuu';
  final buffer = StringBuffer();
  for (final rune in text.toLowerCase().runes) {
    final char = String.fromCharCode(rune);
    final index = from.indexOf(char);
    buffer.write(index >= 0 ? to[index] : char);
  }
  return buffer.toString().split(RegExp(r'[^a-z0-9]+')).where((w) => w.isNotEmpty).toList();
}

/// Radio Browser is crowdsourced, so one real stream is often registered
/// several times under different `stationuuid`s (and sometimes a cache-
/// busting `?timestamp` on the URL). Two entries are the same stream when
/// their host, port and path match — scheme, query string and a trailing
/// `/` or `;` are ignored. Host alone is NOT enough: e.g. every Rádio
/// Cidade channel shares `streamtheworld.com` and differs only by path.
///
/// Keeps the first entry of each group; the API already returns most-voted
/// first, so that is the most trusted copy. Order is preserved. Does not
/// catch the same station under different paths (Antena 1's `/stream` vs.
/// `/sm`) — that would need a name/frequency heuristic that risks merging
/// genuinely different stations.
List<RadioStation> dedupeStationsByStream(List<RadioStation> stations) {
  final seen = <String>{};
  return [
    for (final station in stations)
      if (seen.add(_streamKey(station.streamUrl))) station,
  ];
}

String _streamKey(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.host.isEmpty) return url;
  final path = uri.path.replaceAll(RegExp(r'[/;]+$'), '');
  final port = uri.hasPort ? ':${uri.port}' : '';
  return '${uri.host.toLowerCase()}$port$path';
}
