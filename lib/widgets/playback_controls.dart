import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'round_button.dart';

/// Previous / play-pause / next — the big transport row on the home
/// screen. The center button turns into a refresh icon in
/// [isRefreshMode] (see that field's own doc) instead of being a second,
/// separate "tentar novamente" control elsewhere on the screen.
class PlaybackControls extends StatelessWidget {
  final bool isPlaying;
  final bool isLoading;
  final bool hasStation;
  // WHY the big center button can turn into a refresh icon: by explicit
  // request, replacing the "Tentar novamente" text button that used to
  // live in EmptyStationCard when the "Todas" list fails to load or
  // comes back empty. There is no station to play in that situation
  // anyway (the center button would just be disabled), so reusing it as
  // the actual retry control — instead of a second, separate button
  // elsewhere on the screen — means one clear action in one familiar
  // place. `_HomeContent` computes `stationsUnavailable` and passes it
  // straight through as this flag, plus `onRefresh` calling
  // `ref.invalidate(stationsProvider)`. It flips back to a normal
  // play/pause icon on its own the next time this rebuilds with a
  // non-empty, error-free station list — no separate "done refreshing"
  // signal needed, since that rebuild only happens once the underlying
  // provider actually has one.
  final bool isRefreshMode;
  final VoidCallback onPrevious;
  final VoidCallback onTogglePlay;
  final VoidCallback onNext;
  final VoidCallback? onRefresh;

  const PlaybackControls({
    super.key,
    required this.isPlaying,
    required this.isLoading,
    required this.hasStation,
    this.isRefreshMode = false,
    required this.onPrevious,
    required this.onTogglePlay,
    required this.onNext,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    // In refresh mode there is deliberately no station to play (an empty
    // list has nothing to skip to either), so the center button stays
    // tappable on its own condition instead of `hasStation`.
    final canTapCenter = isRefreshMode ? true : hasStation;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        RoundButton(icon: Icons.skip_previous, tooltip: 'Estação anterior', size: 76, onTap: hasStation ? onPrevious : null),
        const SizedBox(width: 26),
        Material(
          color: AppColors.primary,
          shape: const CircleBorder(),
          elevation: 4,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: canTapCenter ? (isRefreshMode ? onRefresh : onTogglePlay) : null,
            child: SizedBox(
              width: 92,
              height: 92,
              child: Center(
                child: isLoading
                    ? const SizedBox(
                        width: 30,
                        height: 30,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                      )
                    : Icon(
                        isRefreshMode ? Icons.refresh : (isPlaying ? Icons.pause : Icons.play_arrow),
                        color: Colors.white,
                        size: 40,
                        semanticLabel: isRefreshMode ? 'Tentar novamente' : 'Tocar ou pausar',
                      ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 26),
        RoundButton(icon: Icons.skip_next, tooltip: 'Próxima estação', size: 76, onTap: hasStation ? onNext : null),
      ],
    );
  }
}
