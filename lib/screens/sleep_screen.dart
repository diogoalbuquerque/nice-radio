// Sleep-timer picker, a full screen like `StationListScreen` (reached from the
// header's "Dormir" button). Picking an option applies it and goes back.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/player_provider.dart';
import '../services/analytics_service.dart';
import '../widgets/sleep_options.dart';

class SleepScreen extends ConsumerWidget {
  const SleepScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(playerProvider.select((p) => p.sleepMinutes));
    final remaining = ref.watch(playerProvider.select((p) => p.sleepRemainingMinutes));

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
                      ref.trackTap('sleep_back');
                      Navigator.of(context).pop();
                    },
                  ),
                  const SizedBox(width: 6),
                  const Text('Dormir', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            Expanded(
              child: SleepOptions(
                selectedMinutes: selected,
                remainingMinutes: remaining,
                onSelect: (minutes) {
                  ref.trackTap('sleep_option');
                  ref.read(playerProvider.notifier).setSleepMinutes(minutes);
                  Navigator.of(context).pop();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
