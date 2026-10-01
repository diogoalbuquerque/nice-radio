import 'package:flutter/material.dart';

import 'choice_pill.dart';
import 'section_card.dart';

const _sleepOptions = [0, 30, 60, 120];

/// The sleep-timer picker that expands under "Dormir" on the home screen.
class SleepPanel extends StatelessWidget {
  final int selectedMinutes;
  final ValueChanged<int> onSelect;

  const SleepPanel({super.key, required this.selectedMinutes, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Desligar a rádio sozinha em:', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 2.6,
            children: _sleepOptions.map((minutes) {
              return ChoicePill(
                label: minutes == 0 ? 'Não desligar' : '$minutes minutos',
                selected: selectedMinutes == minutes,
                onTap: () => onSelect(minutes),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
