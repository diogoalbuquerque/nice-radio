import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The "Rádio não disponível" banner shown under the playback controls
/// whenever [PlayerNotifier] reports a connection failure.
class ErrorBanner extends StatelessWidget {
  final String message;

  const ErrorBanner({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.favoriteTint,
        border: Border.all(color: AppColors.favoriteBorder, width: 1.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: AppColors.favoriteText, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.favoriteText),
            ),
          ),
        ],
      ),
    );
  }
}
