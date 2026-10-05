// Fetches the station list for the user's state and exposes the Favoritas /
// Todas filter. [visibleStationsProvider] is the one place that decides "which
// stations to show right now", shared by the home and station-list screens.
// Pure list logic (sort, dedupe, search) lives in `utils/station_lists.dart`.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/radio_station.dart';
import '../services/radio_browser_service.dart';
import '../utils/station_lists.dart';
import 'favorites_provider.dart';
import 'settings_provider.dart';

enum StationViewMode { favorites, all }

/// Which Favoritas/Todas tab is selected. Persisted: a remembered choice is not
/// a guess, and the default stays "Todas".
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

/// [viewModeProvider] as a plain value ("Todas" while it loads), so readers do
/// not juggle an `AsyncValue`. Same idea as [favoritesProviderOrEmpty].
final viewModeProviderOrAll = Provider<StationViewMode>((ref) {
  return ref.watch(viewModeProvider).value ?? StationViewMode.all;
});

final radioBrowserServiceProvider = Provider<RadioBrowserService>((ref) {
  return RadioBrowserService();
});

/// The raw station list for the selected state, sorted like a radio dial and
/// de-duplicated by stream.
///
/// Watches `settingsProvider.select(selectedState)`, never the whole settings
/// future: settings change every 5s while playing (data-usage counter), and
/// watching all of it re-fetched the entire list every 5s (it made the
/// "Buscando rádios..." footer flicker during normal playback).
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

/// [favoritesProvider] as a plain set (empty while it loads).
final favoritesProviderOrEmpty = Provider<Set<String>>((ref) {
  return ref.watch(favoritesProvider).value ?? const {};
});
