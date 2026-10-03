// App version, manual state picker (the fallback path when automatic
// location detection was skipped or failed), and the data usage counter
// with its reset button.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../providers/player_provider.dart';
import '../providers/settings_provider.dart';
import '../theme/app_theme.dart';
import '../utils/brazilian_states.dart';
import '../widgets/about_sheet.dart';
import '../widgets/choice_pill.dart';
import '../widgets/section_card.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _statePickerOpen = false;

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 12, 22, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    tooltip: 'Voltar',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Text('Configurações', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            Expanded(
              child: settingsAsync.when(
                data: (settings) => ListView(
                  padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
                  children: [
                    _SettingsCard(
                      label: 'Estado',
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              settings.selectedState ?? 'Nenhum escolhido',
                              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                            ),
                            TextButton(
                              onPressed: () => setState(() => _statePickerOpen = !_statePickerOpen),
                              style: TextButton.styleFrom(
                                backgroundColor: AppColors.subtleBackground,
                                foregroundColor: AppColors.primary,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              ),
                              child: Text(_statePickerOpen ? 'Fechar' : 'Trocar', style: const TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                        if (_statePickerOpen) ...[
                          const SizedBox(height: 10),
                          ...BrazilianStates.all.map((uf) {
                            final selected = uf.name == settings.selectedState;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              // Without this, each pill would shrink-wrap
                              // to its own label's width (short names like
                              // "Acre" ending up tiny, "Mato Grosso do Sul"
                              // huge) — forcing full width keeps every
                              // state pill the same size.
                              child: SizedBox(
                                width: double.infinity,
                                child: ChoicePill(
                                  label: uf.name,
                                  selected: selected,
                                  trailing: selected ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
                                  onTap: () {
                                    notifier.selectState(uf.name);
                                    // A stale "Rádio não disponível" banner
                                    // belongs to the previous state's
                                    // station — see PlayerNotifier
                                    // .clearError's own doc for why picking
                                    // a new state clears it, reported
                                    // directly.
                                    ref.read(playerProvider.notifier).clearError();
                                    setState(() => _statePickerOpen = false);
                                  },
                                ),
                              ),
                            );
                          }),
                        ],
                      ],
                    ),
                    const SizedBox(height: 16),
                    _DataUsageCard(
                      dataUsedBytes: settings.dataUsedBytes,
                      dataUsedSince: settings.dataUsedSince,
                      onReset: notifier.resetDataUsage,
                    ),
                    const SizedBox(height: 16),
                    const _AboutCard(),
                  ],
                ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) => const Center(child: Text('Não foi possível carregar as configurações.')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final String label;
  final List<Widget> children;

  const _SettingsCard({required this.label, required this.children});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      padding: const EdgeInsets.all(20),
      borderRadius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textSecondary, letterSpacing: 0.4),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

class _DataUsageCard extends StatelessWidget {
  final int dataUsedBytes;
  final DateTime dataUsedSince;
  final Future<void> Function() onReset;

  const _DataUsageCard({required this.dataUsedBytes, required this.dataUsedSince, required this.onReset});

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      label: 'Dados usados',
      children: [
        Text(_formatBytes(dataUsedBytes), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text('Desde ${_formatDate(dataUsedSince)}', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: onReset,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textPrimary,
            side: BorderSide(color: AppColors.border, width: 1.5),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          ),
          child: const Text('Zerar contador', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  /// Formats a byte count the way a person reads it, not the way a
  /// computer stores it: MB below 1 GB, GB above, one decimal place.
  static String _formatBytes(int bytes) {
    const oneMb = 1024 * 1024;
    const oneGb = oneMb * 1024;
    if (bytes < oneMb) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    if (bytes < oneGb) return '${(bytes / oneMb).toStringAsFixed(0)} MB';
    return '${(bytes / oneGb).toStringAsFixed(2)} GB';
  }

  static String _formatDate(DateTime date) {
    const months = [
      'janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho',
      'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro',
    ];
    return '${date.day} de ${months[date.month - 1]} de ${date.year}';
  }
}

class _AboutCard extends StatelessWidget {
  const _AboutCard();

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      label: 'Sobre',
      children: [
        // The whole row is the tap target (big, easy to hit) and opens the
        // About sheet; the chevron signals that it is tappable.
        Semantics(
          button: true,
          label: 'Sobre o Nice Radio. Abrir detalhes do aplicativo',
          excludeSemantics: true,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => showAboutSheet(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  const Expanded(child: Text('Versão do aplicativo', style: TextStyle(fontSize: 16))),
                  FutureBuilder<PackageInfo>(
                    future: PackageInfo.fromPlatform(),
                    builder: (context, snapshot) {
                      final version = snapshot.data?.version ?? '1.0.0';
                      return Text(version, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textSecondary));
                    },
                  ),
                  const SizedBox(width: 6),
                  Icon(Icons.chevron_right, color: AppColors.textSecondary),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
