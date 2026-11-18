import 'package:flutter/material.dart';

import 'round_button.dart';

/// The header's "Dormir" button: a moon icon, with the minutes left as a
/// badge while a timer runs (a round button has no room for "Dormir 25min").
class SleepButton extends StatelessWidget {
  final int minutes;
  final Color color;
  final VoidCallback onTap;

  const SleepButton({super.key, required this.minutes, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return RoundButton(
      iconWidget: Badge(
        isLabelVisible: minutes > 0,
        label: Text('$minutes'),
        child: Icon(Icons.bedtime, color: color),
      ),
      tooltip: minutes > 0 ? 'Dormir: faltam $minutes minutos' : 'Dormir',
      iconSize: 22,
      padding: const EdgeInsets.all(12),
      onTap: onTap,
    );
  }
}
