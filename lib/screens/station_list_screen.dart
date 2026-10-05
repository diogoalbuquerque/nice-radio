// Full list of stations for the user's state, with the same
// Favoritas/Todas filter as the home screen (see visibleStationsProvider
// for why that filter logic is shared, not duplicated, between the two
// screens).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/radio_station.dart';
import '../providers/favorites_provider.dart';
import '../providers/player_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/stations_provider.dart';
import '../services/analytics_service.dart';
import '../theme/app_theme.dart';
import '../widgets/segmented_toggle.dart';
import '../widgets/station_avatar.dart';

class StationListScreen extends ConsumerWidget {
  const StationListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewMode = ref.watch(viewModeProviderOrAll);
    final visibleStations = ref.watch(visibleStationsProvider);
    final currentStationId = ref.watch(playerProvider.select((player) => player.currentStation?.id));
    final favoriteIds = ref.watch(favoritesProviderOrEmpty);
    final stateName = ref.watch(settingsProvider.select((async) => async.value?.selectedState)) ?? '';

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    tooltip: 'Voltar',
                    onPressed: () {
                      ref.trackTap('station_list_back');
                      Navigator.of(context).pop();
                    },
                  ),
                  const SizedBox(width: 6),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Estações', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      Text(stateName, style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 16, 22, 0),
              child: SegmentedToggle(
                leftLabel: 'Favoritas',
                rightLabel: 'Todas',
                isLeftSelected: viewMode == StationViewMode.favorites,
                onSelectLeft: () {
                  ref.trackTap('view_favorites', screen: 'station_list');
                  ref.read(viewModeProvider.notifier).showFavorites();
                },
                onSelectRight: () {
                  ref.trackTap('view_all', screen: 'station_list');
                  ref.read(viewModeProvider.notifier).showAll();
                },
              ),
            ),
            Expanded(
              child: visibleStations.when(
                data: (stations) {
                  if (stations.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          'Nenhuma estação aqui ainda.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(22, 16, 22, 26),
                    itemCount: stations.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final station = stations[index];
                      return _StationRow(
                        station: station,
                        isSelected: station.id == currentStationId,
                        isFavorite: favoriteIds.contains(station.id),
                        onTap: () {
                          ref.trackTap('station_select');
                          ref.read(playerProvider.notifier).playStation(station);
                          Navigator.of(context).pop();
                        },
                        onToggleFavorite: () {
                          ref.trackTap('favorite_toggle', screen: 'station_list');
                          ref.read(favoritesProvider.notifier).toggle(station.id);
                        },
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      'Não foi possível buscar as rádios. Verifique sua internet.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StationRow extends StatelessWidget {
  final RadioStation station;
  final bool isSelected;
  final bool isFavorite;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;

  const _StationRow({
    required this.station,
    required this.isSelected,
    required this.isFavorite,
    required this.onTap,
    required this.onToggleFavorite,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isSelected ? AppColors.primaryTint : AppColors.card,
        border: Border.all(color: isSelected ? AppColors.primary : AppColors.border, width: 1.5),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          StationAvatar(station: station, size: 48),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      station.displayName,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      station.genre,
                      style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (isSelected) ...[
            Icon(Icons.graphic_eq, color: AppColors.primary, size: 22),
            const SizedBox(width: 8),
          ],
          IconButton(
            icon: Icon(
              isFavorite ? Icons.star : Icons.star_border,
              color: isFavorite ? AppColors.favorite : AppColors.textSecondary,
            ),
            tooltip: isFavorite ? 'Remover dos favoritos' : 'Favoritar',
            onPressed: onToggleFavorite,
          ),
        ],
      ),
    );
  }
}
