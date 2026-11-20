import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The small "copy song title" button next to "TOCANDO AGORA" on
/// [StationCard] — flips to a checkmark briefly after a tap (see
/// `HomeScreen`'s `_justCopied` state).
class CopyIconButton extends StatelessWidget {
  final bool justCopied;
  final VoidCallback onTap;

  const CopyIconButton({super.key, required this.justCopied, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.subtleBackground,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(
            justCopied ? Icons.check : Icons.copy,
            size: 18,
            color: AppColors.primary,
            semanticLabel: 'Copiar nome da música',
          ),
        ),
      ),
    );
  }
}
