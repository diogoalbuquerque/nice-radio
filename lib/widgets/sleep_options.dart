import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'choice_pill.dart';

const sleepOptions = [0, 30, 60, 120, 150, 180];

/// The sleep-timer choices, one big full-width row each (the body of
/// `SleepScreen`). Prop-driven so it is testable without the player.
class SleepOptions extends StatelessWidget {
  /// The chosen option (0 = off); highlights its row.
  final int selectedMinutes;

  /// Minutes still left on a running timer, shown as a hint; 0 hides it.
  final int remainingMinutes;
  final ValueChanged<int> onSelect;

  const SleepOptions({super.key, required this.selectedMinutes, required this.remainingMinutes, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 18),
      children: [
        const Text('Desligar a rádio sozinha em:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        if (remainingMinutes > 0) ...[
          const SizedBox(height: 4),
          Text('Faltam $remainingMinutes min', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
        ],
        const SizedBox(height: 14),
        for (final minutes in sleepOptions) ...[
          ChoicePill(
            label: minutes == 0 ? 'Não desligar' : '$minutes minutos',
            selected: selectedMinutes == minutes,
            onTap: () => onSelect(minutes),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}
