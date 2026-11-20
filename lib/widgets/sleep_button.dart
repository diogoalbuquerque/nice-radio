import 'package:flutter/material.dart';

import 'round_button.dart';

/// The header's "Dormir" button: a moon icon, with the minutes left as a
/// red pill with the number centered on it while a timer runs.
class SleepButton extends StatelessWidget {
  final int minutes;
  final Color color;
  final VoidCallback onTap;

  const SleepButton({super.key, required this.minutes, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return RoundButton(
      iconWidget: SizedBox.square(
        dimension: 22,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Icon(Icons.snooze, color: color),
            // Red pill centered on the icon: the red is what gives the number
            // contrast. Fixed max size + `scaleDown` keep it inside the button
            // at any system font size.
            if (minutes > 0)
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 22, maxWidth: 34, minHeight: 22, maxHeight: 22),
                child: DecoratedBox(
                  decoration: BoxDecoration(color: Theme.of(context).colorScheme.error, borderRadius: BorderRadius.circular(11)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '$minutes',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, height: 1.4, color: Theme.of(context).colorScheme.onError),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      tooltip: minutes > 0 ? 'Dormir: faltam $minutes minutos' : 'Dormir',
      iconSize: 22,
      padding: const EdgeInsets.all(12),
      onTap: onTap,
    );
  }
}
