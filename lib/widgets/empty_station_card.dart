import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/radio_station.dart';
import '../providers/stations_provider.dart';
import 'section_card.dart';

/// Shown instead of [StationCard] when there is nothing to play yet for
/// the current Favoritas/Todas tab — an empty favorites list, an empty
/// "Todas" (no stations for this state, or a fetch that hasn't returned
/// anything), or a genuine fetch error. The retry action for the last two
/// lives on the big play/pause button itself (see `PlaybackControls`'
/// `isRefreshMode`) — this card only points at it.
class EmptyStationCard extends StatelessWidget {
  final AsyncValue<List<RadioStation>> visibleStations;
  final StationViewMode viewMode;

  const EmptyStationCard({super.key, required this.visibleStations, required this.viewMode});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      padding: const EdgeInsets.all(22),
      borderRadius: 20,
      child: visibleStations.when(
        data: (list) {
          if (list.isNotEmpty) {
            return const Text('Toque em uma rádio para começar a ouvir.', textAlign: TextAlign.center);
          }
          // WHY this checks `viewMode` instead of always showing the same
          // "nenhuma estação favoritada" text: reported directly — an
          // empty "Todas" list (no stations found for the selected
          // state, or the API genuinely returned none) showed that exact
          // favorites-only message, which makes no sense on "Todas" since
          // favoriting was never the issue there.
          if (viewMode == StationViewMode.favorites) {
            return const Text(
              'Você ainda não adicionou nenhuma estação favorita. Navegue entre '
              'todas as estações e escolha as suas preferidas.',
              textAlign: TextAlign.center,
            );
          }
          // WHY there is no "Tentar novamente" button here anymore (there
          // used to be one, calling `ref.invalidate(stationsProvider)`):
          // by explicit request, that retry action moved onto the big
          // play/pause button itself — see `PlaybackControls`' own
          // `isRefreshMode` doc and `_HomeContent`'s `stationsUnavailable`
          // for where it now lives. This card just points at it.
          return const Text(
            'Nenhuma estação foi encontrada para o seu estado no momento. '
            'Toque no ícone de atualizar abaixo para tentar novamente.',
            textAlign: TextAlign.center,
          );
        },
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (_, _) => const Text(
          'Não foi possível buscar as rádios agora. Toque no ícone de '
          'atualizar abaixo para tentar novamente.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
