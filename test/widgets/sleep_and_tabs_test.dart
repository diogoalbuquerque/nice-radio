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
}
