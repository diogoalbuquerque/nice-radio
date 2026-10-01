// Shown after 3 connection attempts fail in a row (see
// PlayerNotifier._setPlaybackError / PlayerState.stationsOfflineTrigger,
// and home_screen.dart's ref.listen on it) — reassures the person that
// it's the stations, not the app or their own connection, and lets them
// opt out of seeing it again. A first attempt at this feature fired on
// every single failure instead of waiting for 3 — reverted after
// explicit user feedback that this was a misunderstanding of the
// original request; the inline error banner under the play controls
// already gives immediate feedback on a single bad station (including
// one stuck on a connection timeout — see PlayerNotifier's own
// `readyToPlay` guard in `_setPlaybackError`), so this dialog only
// needs to step in for the less common, more worrying case of several
// stations failing in a row.
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A dialog telling the person that several stations failed to connect
/// in a row. Its "Não mostrar novamente" checkbox comes pre-checked —
/// most people who just tap "Entendi" through end up suppressing future
/// dialogs from that point on; anyone who wants to keep being reminded
/// can uncheck it first. See [show] for how the result is meant to be
/// used.
class StationsOfflineDialog extends StatefulWidget {
  const StationsOfflineDialog({super.key});

  /// Shows the dialog and returns the checkbox's final state: `true`
  /// means "não mostrar novamente" stayed checked (suppress from now
  /// on), `false` means the person explicitly unchecked it (keep
  /// showing every 3 failures). Returns `null` if dismissed without the
  /// "Entendi" button — the barrier is non-dismissible and there is no
  /// other close control, so this only happens via the system back
  /// gesture; callers should leave the stored preference untouched in
  /// that case, since no explicit choice was made.
  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const StationsOfflineDialog(),
    );
  }

  @override
  State<StationsOfflineDialog> createState() => _StationsOfflineDialogState();
}

class _StationsOfflineDialogState extends State<StationsOfflineDialog> {
  // Pre-checked by design — see the class doc.
  bool _dontShowAgain = true;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _OfflineTowerIcon(),
            const SizedBox(height: 20),
            Text(
              'Ah, não!',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              'Algumas estações estão fora do ar agora. Não se preocupe, '
              'tente novamente mais tarde ou explore as outras opções '
              'disponíveis.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, height: 1.4, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            InkWell(
              onTap: () => setState(() => _dontShowAgain = !_dontShowAgain),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Checkbox(
                      value: _dontShowAgain,
                      activeColor: AppColors.primary,
                      onChanged: (value) => setState(() => _dontShowAgain = value ?? true),
                    ),
                    Flexible(
                      child: Text(
                        'Não mostrar novamente',
                        style: TextStyle(fontSize: 15, color: AppColors.textPrimary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () => Navigator.of(context).pop(_dontShowAgain),
                child: const Text('Entendi', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A radio tower with an "X" over it — built from two Material icons
/// rather than a bundled image asset, the same way every other icon in
/// this app is (e.g. the lamp "modo noturno" toggle, `LampIcon` in
/// `lib/widgets/`), and in the app's own palette (`AppColors.primary`
/// for the tower, `AppColors.favorite` — the app's one non-blue accent,
/// already reused for error states by `ErrorBanner` in
/// `lib/widgets/` — for the "X"). This app never introduces a color
/// outside that blue+orange palette (see `AppColors`' own class doc, and
/// the "no green" rule it explains), so an ad-hoc red "error icon" was
/// never on the table here. The "X" has no background of its own — a
/// filled badge made it read as a second, competing shape rather than a
/// mark over the tower (an earlier version, corrected after visual
/// review) — and it is centered directly over the tower, not tucked in
/// a corner (a second earlier version, corrected the same way): with no
/// background, overlapping the tower reads as "the tower, crossed out",
/// which is what "sem sinal" (no signal) is meant to say.
class _OfflineTowerIcon extends StatelessWidget {
  const _OfflineTowerIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(color: AppColors.primaryTint, shape: BoxShape.circle),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(Icons.cell_tower, size: 44, color: AppColors.primary),
          Icon(Icons.close, size: 38, color: AppColors.favorite),
        ],
      ),
    );
  }
}
