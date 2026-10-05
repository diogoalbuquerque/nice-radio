import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/player_provider.dart';
import '../services/analytics_service.dart';
import '../theme/app_theme.dart';
import 'round_button.dart';
import 'section_card.dart';

/// The volume percentage plus its +/- buttons. Reads [playerProvider]
/// directly (via [Consumer], instead of taking a notifier as a
/// constructor parameter) since the +/- actions have nowhere else to go —
/// this is the one card on the home screen that both displays and acts on
/// provider state by itself.
class VolumeCard extends StatelessWidget {
  final int volumePercent;

  const VolumeCard({super.key, required this.volumePercent});

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final notifier = ref.read(playerProvider.notifier);
        return SectionCard(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.volume_down, size: 18, color: AppColors.textSecondary),
                  const SizedBox(width: 8),
                  Text('VOLUME', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textSecondary, letterSpacing: 0.4)),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  RoundButton(
                    icon: Icons.remove,
                    tooltip: 'Diminuir volume',
                    size: 56,
                    onTap: volumePercent <= 0
                        ? null
                        : () {
                            ref.trackTap('volume_down');
                            notifier.decreaseVolume();
                          },
                  ),
                  Expanded(
                    child: Text(
                      '$volumePercent%',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                    ),
                  ),
                  RoundButton(
                    icon: Icons.add,
                    tooltip: 'Aumentar volume',
                    size: 56,
                    onTap: volumePercent >= 100
                        ? null
                        : () {
                            ref.trackTap('volume_up');
                            notifier.increaseVolume();
                          },
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
