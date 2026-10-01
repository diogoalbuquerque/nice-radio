import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Shown when the app has no state to search yet — either onboarding was
/// skipped, or automatic location detection failed. This is the same
/// "always have a manual way in" fallback.
///
/// Takes [onChooseState] rather than navigating to Settings itself, so
/// this widget (like everything else in `lib/widgets/`) has no reason to
/// know about `lib/screens/` — the screen that uses this one decides
/// where "choose my state" actually goes.
class NoStateSelected extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onChooseState;

  const NoStateSelected({super.key, required this.isLoading, required this.onChooseState});

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Center(child: CircularProgressIndicator());

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.location_off, size: 48, color: AppColors.textSecondary),
            const SizedBox(height: 16),
            const Text(
              'Ainda não sabemos o seu estado',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Escolha o seu estado para vermos as rádios da sua região.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: onChooseState,
                child: const Text('Escolher meu estado', style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
