// The "Sobre" bottom sheet: icon, name, version, what the app does and why
// it exists. Opened from the version row in Settings.
//
// Lives in `widgets/` (not `screens/`) because it is a self-contained piece
// that needs nothing from the rest of the app.
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../theme/app_theme.dart';

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
    (Icons.my_location, 'As principais estações do seu estado'),
    (Icons.play_circle_fill, 'Funcionalidades pensadas para facilitar'),
    (Icons.star, 'Escolha suas estações favoritas'),
    (Icons.bedtime, 'Temporizador para dormir ouvindo rádio'),
    (Icons.lightbulb, 'Modo noturno'),
    (Icons.mic, 'Atalhos e comandos de voz para tocar sem mexer na tela'),
  ];

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
          'descobrir o seu estado, e não é guardada nem enviada.',
          style: TextStyle(fontSize: 17, height: 1.4),
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
