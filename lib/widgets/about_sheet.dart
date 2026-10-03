// The "Sobre" bottom sheet: icon, name, version, what the app does and why
// it exists, and who made it. Opened from the version row in Settings.
//
// Lives in `widgets/` (not `screens/`) because it is a self-contained piece
// that needs nothing from the rest of the app; the repository link is a
// parameter-free constant here because it never changes per build.
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';

const niceRadioRepositoryUrl = 'https://github.com/diogoalbuquerque/nice-radio';

/// Slides up from the bottom and can be dragged to full height, because at
/// large accessibility text sizes the content does not fit in half a screen.
Future<void> showAboutSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.background,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, controller) => _AboutContent(controller: controller),
    ),
  );
}

class _AboutContent extends StatelessWidget {
  final ScrollController controller;

  const _AboutContent({required this.controller});

  static const _features = [
    (Icons.my_location, 'Estações do seu estado, encontradas automaticamente'),
    (Icons.play_circle_fill, 'Um botão grande para tocar e pausar'),
    (Icons.volume_up, 'Volume em passos de 10%, direto no volume do celular'),
    (Icons.star, 'Estrelinha para guardar as estações favoritas'),
    (Icons.music_note, 'Mostra a música que está tocando, quando a rádio informa'),
    (Icons.bedtime, 'Temporizador para dormir ouvindo rádio'),
    (Icons.lightbulb, 'Modo noturno, ligado só quando você quiser'),
    (Icons.mic, 'Atalhos e comandos de voz para tocar sem mexer na tela'),
  ];

  Future<void> _openRepository(BuildContext context) async {
    final opened = await launchUrl(Uri.parse(niceRadioRepositoryUrl), mode: LaunchMode.externalApplication)
        .catchError((_) => false);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir o link.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      children: [
        Center(
          child: Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(3)),
          ),
        ),
        const SizedBox(height: 20),
        Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Image.asset(
              'assets/icon/icon.png',
              width: 96,
              height: 96,
              semanticLabel: 'Ícone do Nice Radio',
            ),
          ),
        ),
        const SizedBox(height: 14),
        const Center(child: Text('Nice Radio', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold))),
        const SizedBox(height: 2),
        Center(
          child: FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (context, snapshot) => Text(
              'Versão ${snapshot.data?.version ?? ''}'.trim(),
              style: TextStyle(fontSize: 15, color: AppColors.textSecondary),
            ),
          ),
        ),
        const SizedBox(height: 22),
        const _Heading('O que é'),
        const Text(
          'Um rádio de internet feito para ser fácil de usar. Em uma única tela você escolhe a estação, '
          'toca e pausa, ajusta o volume e guarda suas favoritas.',
          style: TextStyle(fontSize: 17, height: 1.4),
        ),
        const SizedBox(height: 22),
        const _Heading('Principais funções'),
        for (final (icon, text) in _features)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 22, color: AppColors.primary),
                const SizedBox(width: 12),
                Expanded(child: Text(text, style: const TextStyle(fontSize: 16, height: 1.35))),
              ],
            ),
          ),
        const SizedBox(height: 12),
        const _Heading('Por que foi criado'),
        const Text(
          'O Nice Radio nasceu para que idosos e pessoas com deficiência consigam ouvir rádio com '
          'autonomia: botões grandes, letras fáceis de ler, cores pensadas para quem tem baixa visão '
          'ou daltonismo, e compatibilidade com leitores de tela e comandos de voz.',
          style: TextStyle(fontSize: 17, height: 1.4),
        ),
        const SizedBox(height: 22),
        const _Heading('Seguro e sem propagandas'),
        const Text(
          'Sem anúncios, sem cadastro e sem senha. Sua localização é usada uma única vez, só para '
          'descobrir o seu estado, e não é guardada nem enviada. O código é aberto: qualquer pessoa '
          'pode conferir.',
          style: TextStyle(fontSize: 17, height: 1.4),
        ),
        const SizedBox(height: 26),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.card,
            border: Border.all(color: AppColors.border, width: 1.5),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'DESENVOLVIDO POR',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textSecondary, letterSpacing: 0.4),
              ),
              const SizedBox(height: 6),
              const Text('Diogo Albuquerque', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Semantics(
                button: true,
                label: 'Abrir o repositório do aplicativo no GitHub',
                excludeSemantics: true,
                child: OutlinedButton.icon(
                  onPressed: () => _openRepository(context),
                  icon: const Icon(Icons.code),
                  label: const Text('Ver código no GitHub', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: BorderSide(color: AppColors.primary, width: 1.5),
                    minimumSize: const Size.fromHeight(52),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  final String text;

  const _Heading(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        header: true,
        child: Text(text, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
