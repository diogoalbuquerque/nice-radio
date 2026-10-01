// Fetches the station list for the user's current state and exposes the
// "Favoritas" / "Todas" filter that both the home screen and the station
// list screen use.
//
// WHY the favorites filter lives here and not duplicated in each screen:
// the home screen and the station-list screen both need "the list of
// stations to show right now", filtered the same way. Computing that in
// one derived provider ([visibleStationsProvider]) instead of copy-pasting
// the filter logic into two widgets is what actually avoids duplication —
// a shared *widget* helps with duplicated markup, a shared *provider*
// is what avoids duplicated logic.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/radio_station.dart';
import '../services/radio_browser_service.dart';
import 'favorites_provider.dart';
import 'settings_provider.dart';

enum StationViewMode { favorites, all }

/// Which filter tab is selected — persisted to disk (via
/// `StorageService.getViewModeIsFavorites`/`setViewModeIsFavorites`) by
/// explicit request, so reopening the app shows the same tab the person
/// had selected last, not always "Todas". This used to be deliberately
/// *not* persisted, on the reasoning that defaulting to "all stations"
/// was the safer choice for someone who favorited nothing yet — that
/// reasoning no longer applies now that this is a remembered choice,
/// not a guess: a person who explicitly picked "Favoritas" gets exactly
/// that list back, and a person who never touched the toggle still
/// starts on "Todas" either way, since that is [build]'s default before
/// anything has ever been saved.
class ViewModeNotifier extends AsyncNotifier<StationViewMode> {
  @override
  Future<StationViewMode> build() async {
    final isFavorites = await ref.read(storageServiceProvider).getViewModeIsFavorites();
    return isFavorites ? StationViewMode.favorites : StationViewMode.all;
  }

  Future<void> showFavorites() async {
    await ref.read(storageServiceProvider).setViewModeIsFavorites(true);
    state = const AsyncData(StationViewMode.favorites);
  }

  Future<void> showAll() async {
    await ref.read(storageServiceProvider).setViewModeIsFavorites(false);
    state = const AsyncData(StationViewMode.all);
  }
}

final viewModeProvider = AsyncNotifierProvider<ViewModeNotifier, StationViewMode>(
  ViewModeNotifier.new,
);

/// [viewModeProvider] is itself async (it loads the last-selected tab
/// from disk); this reads it as a plain [StationViewMode], defaulting to
/// "Todas" while it loads, mirroring [favoritesProviderOrEmpty] just
/// below, so nothing that reads the current tab has to juggle an
/// AsyncValue — including, briefly, on cold start, before the disk read
/// finishes (typically well under a frame).
final viewModeProviderOrAll = Provider<StationViewMode>((ref) {
  return ref.watch(viewModeProvider).value ?? StationViewMode.all;
});

final radioBrowserServiceProvider = Provider<RadioBrowserService>((ref) {
  return RadioBrowserService();
});

/// The raw station list for whatever state is currently selected.
///
/// WHY `FutureProvider` (not `AsyncNotifier`) is enough here: this
/// provider has no methods of its own — it only needs to re-fetch
/// whenever the selected state changes, which `ref.watch` already gives
/// us for free. Reaching for a full Notifier class would be unnecessary
/// ceremony for "just refetch when this input changes".
///
/// WHY `settingsProvider.select(...)` and not `await
/// settingsProvider.future`: this provider must only re-fetch when
/// `selectedState` itself changes — not on *every* settings change.
/// `settingsProvider`'s state is a single `AppSettings` object covering
/// unrelated fields too, including the data-usage counter that
/// `PlayerNotifier` updates every 5 seconds while a station plays (see
/// `_startDataUsageTicker`). Watching the whole future meant a *new*
/// `AppSettings` object — with only `dataUsedBytes` different — counted
/// as "the input changed", so this provider re-ran and re-fetched the
/// entire station list from the Radio Browser API every 5 seconds a
/// station was playing: a real, live bug, not just wasted network
/// calls — it's what caused the "Buscando rádios..." footer text to
/// keep flickering back in in the middle of normal playback.
/// `select` only triggers a rebuild when the *selected* value
/// (`selectedState` here) actually changes, so the data-usage ticks no
/// longer have any effect on this provider at all.
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

final stationsProvider = FutureProvider<List<RadioStation>>((ref) async {
  final stateName = ref.watch(settingsProvider.select((s) => s.value?.selectedState));
  if (stateName == null) return const [];

  final stations = await ref.read(radioBrowserServiceProvider).fetchStationsByState(stateName);
  return sortStationsByFrequency(dedupeStationsByStream(stations));
});

/// What the UI should actually render: [stationsProvider]'s list, filtered
/// by [viewModeProvider] against the favorited ids.
final visibleStationsProvider = Provider<AsyncValue<List<RadioStation>>>((ref) {
  final stationsAsync = ref.watch(stationsProvider);
  final viewMode = ref.watch(viewModeProviderOrAll);
  final favoriteIds = ref.watch(favoritesProviderOrEmpty);

  return stationsAsync.whenData((stations) {
    if (viewMode == StationViewMode.all) return stations;
    return stations.where((s) => favoriteIds.contains(s.id)).toList();
  });
});

/// [favoritesProvider] is itself async (it loads from disk); this reads
/// it as a plain `Set<String>`, defaulting to empty while it loads,
/// so [visibleStationsProvider] above does not have to juggle two nested
/// AsyncValues at once.
final favoritesProviderOrEmpty = Provider<Set<String>>((ref) {
  return ref.watch(favoritesProvider).value ?? const {};
});
