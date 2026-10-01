import 'package:flutter/material.dart';

import '../models/radio_station.dart';
import '../theme/app_theme.dart';
import 'copy_icon_button.dart';
import 'scrolling_text.dart';
import 'section_card.dart';
import 'station_avatar.dart';

/// The main "what's playing" card on the home screen: the station's
/// avatar/genre/name, and — when the stream sends one — the current song
/// title with a copy button.
class StationCard extends StatelessWidget {
  final RadioStation station;
  final String? nowPlaying;
  final bool justCopied;
  final VoidCallback onCopy;

  const StationCard({
    super.key,
    required this.station,
    required this.nowPlaying,
    required this.justCopied,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      borderRadius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              StationAvatar(station: station, size: 72),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.chipBackground,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        station.genre,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.primary),
                      ),
                    ),
                    const SizedBox(height: 5),
                    ScrollingText(
                      text: station.displayName,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // "Tocando agora" only appears when the stream actually sent a
          // song title — see PlayerNotifier's ICY metadata listener. Many
          // stations never send one, and hiding the block entirely (over
          // showing an empty/placeholder one) was an explicit request.
          if (nowPlaying != null && nowPlaying!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Divider(height: 1, color: AppColors.border),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.music_note, size: 18, color: AppColors.textSecondary),
                const SizedBox(width: 8),
                Text(
                  'TOCANDO AGORA',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textSecondary, letterSpacing: 0.4),
                ),
                const Spacer(),
                CopyIconButton(justCopied: justCopied, onTap: onCopy),
              ],
            ),
            const SizedBox(height: 4),
            ScrollingText(
              text: nowPlaying!,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
  }
}
