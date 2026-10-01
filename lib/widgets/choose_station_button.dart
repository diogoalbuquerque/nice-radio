import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The "Escolher estação" button at the bottom of the home screen, opening
/// the full station list.
class ChooseStationButton extends StatelessWidget {
  final VoidCallback onTap;

  const ChooseStationButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border, width: 1.5),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.list, size: 20),
              SizedBox(width: 10),
              Text('Escolher estação', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }
}
