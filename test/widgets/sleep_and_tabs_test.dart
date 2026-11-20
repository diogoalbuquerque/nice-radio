import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nice_radio/models/radio_station.dart';
import 'package:nice_radio/widgets/segmented_toggle.dart';
import 'package:nice_radio/widgets/sleep_button.dart';
import 'package:nice_radio/widgets/sleep_options.dart';
import 'package:nice_radio/widgets/station_card.dart';

const _station = RadioStation(
  id: 'a',
  name: 'Rádio X',
  streamUrl: 'http://x/stream',
  faviconUrl: null,
  genre: 'Pop',
  state: 'Rio de Janeiro',
  bitrateKbps: 64,
);

Widget _wrap(Widget child) => ProviderScope(child: MaterialApp(home: Scaffold(body: child)));

void main() {
  testWidgets('SleepOptions lists every option and reports the tapped one', (tester) async {
    int? picked;
    await tester.pumpWidget(_wrap(SleepOptions(selectedMinutes: 30, remainingMinutes: 12, onSelect: (m) => picked = m)));

    expect(find.text('Não desligar'), findsOneWidget);
    expect(find.text('30 minutos'), findsOneWidget);
    expect(find.text('Faltam 12 min'), findsOneWidget);
    expect(find.text('150 minutos'), findsOneWidget);
    expect(find.text('180 minutos'), findsOneWidget);

    await tester.tap(find.text('60 minutos'));
    expect(picked, 60);
  });

  testWidgets('SleepButton shows the badge only while a timer runs', (tester) async {
    await tester.pumpWidget(_wrap(SleepButton(minutes: 0, color: Colors.blue, onTap: () {})));
    expect(find.text('0'), findsNothing);

    await tester.pumpWidget(_wrap(SleepButton(minutes: 25, color: Colors.blue, onTap: () {})));
    expect(find.text('25'), findsOneWidget);
  });

  testWidgets('SegmentedToggle draws the tab icons', (tester) async {
    await tester.pumpWidget(_wrap(SegmentedToggle(
      leftLabel: 'Favoritas',
      rightLabel: 'Todas',
      leftIcon: Icons.star,
      rightIcon: Icons.radio,
      isLeftSelected: true,
      onSelectLeft: () {},
      onSelectRight: () {},
    )));
    expect(find.byIcon(Icons.star), findsOneWidget);
    expect(find.byIcon(Icons.radio), findsOneWidget);
  });

  testWidgets('StationCard star toggles favorite', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_wrap(StationCard(
      station: _station,
      nowPlaying: null,
      justCopied: false,
      onCopy: () {},
      isFavorite: false,
      onToggleFavorite: () => taps++,
    )));
    expect(find.byIcon(Icons.star_border), findsOneWidget);
    await tester.tap(find.byTooltip('Favoritar'));
    expect(taps, 1);
  });

  testWidgets('StationCard favorite and copy buttons share the same vertical axis', (tester) async {
    await tester.pumpWidget(_wrap(StationCard(
      station: _station,
      nowPlaying: 'Artista - Música',
      justCopied: false,
      onCopy: () {},
      isFavorite: false,
      onToggleFavorite: () {},
    )));
    final star = tester.getRect(find.ancestor(of: find.byIcon(Icons.star_border), matching: find.byType(Material)).first);
    final copy = tester.getRect(find.ancestor(of: find.byIcon(Icons.copy), matching: find.byType(Material)).first);
    expect(star.center.dx, closeTo(copy.center.dx, 0.5));
    expect(star.width, closeTo(copy.width, 0.5));
  });

  testWidgets('SleepButton centers the minutes on the button at 2x font size', (tester) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        builder: (context, child) =>
            MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2)), child: child!),
        home: Scaffold(body: Center(child: SleepButton(minutes: 120, color: Colors.blue, onTap: () {}))),
      ),
    ));
    final button = tester.getRect(find.byType(SleepButton));
    final text = tester.getRect(find.text('120'));
    expect(text.center.dx, closeTo(button.center.dx, 0.5));
    expect(text.center.dy, closeTo(button.center.dy, 0.5));
    final pill = tester.getRect(find.ancestor(of: find.text('120'), matching: find.byType(DecoratedBox)).first);
    expect(pill.center.dx, closeTo(button.center.dx, 0.5));
    expect(pill.center.dy, closeTo(button.center.dy, 0.5));
    expect(button.contains(pill.topLeft) && button.contains(pill.bottomRight), isTrue);
  });
}
