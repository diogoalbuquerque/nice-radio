// The set of favorited station ids, persisted across app restarts.
//
// WHY this is its own provider instead of living inside AppSettings: it
// changes independently and much more often (every star tap) than the
// rest of settings, and several widgets only care about favorites, not
// the whole settings object. Splitting it out means those widgets only
// rebuild when favorites actually change, not on every settings edit.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'settings_provider.dart' show storageServiceProvider;

class FavoritesNotifier extends AsyncNotifier<Set<String>> {
  @override
  Future<Set<String>> build() async {
    return ref.read(storageServiceProvider).getFavoriteIds();
  }

  Future<void> toggle(String stationId) async {
    final current = state.value ?? const {};
    final updated = Set<String>.from(current);
    if (!updated.remove(stationId)) {
      updated.add(stationId);
    }
    await ref.read(storageServiceProvider).setFavoriteIds(updated);
    state = AsyncData(updated);
  }

  bool isFavorite(String stationId) => (state.value ?? const {}).contains(stationId);
}

final favoritesProvider = AsyncNotifierProvider<FavoritesNotifier, Set<String>>(
  FavoritesNotifier.new,
);
