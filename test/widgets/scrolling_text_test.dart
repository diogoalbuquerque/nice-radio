// Regression coverage for a real bug: ScrollingText used to measure its
// text with a plain TextPainter that ignored the system's text-size
// accessibility setting, while the Marquee it wraps (for text too wide
// to fit) always rendered at the *real*, ambient-scaled size — so at a
// larger text scale, the SizedBox around Marquee was sized for smaller,
// unscaled text than what actually got drawn inside it, clipping the
// real text. See scrolling_text.dart's own WHY comment on `textScaler`.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nice_radio/widgets/scrolling_text.dart';

Widget _wrap(Widget child, {required double textScale, required double width}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(
        body: SizedBox(width: width, child: child),
      ),
    ),
  );
}

void main() {
  group('ScrollingText', () {
    testWidgets('renders a short, fitting text without scrolling', (tester) async {
      await tester.pumpWidget(_wrap(
        const ScrollingText(text: 'Rádio Teste', style: TextStyle(fontSize: 16)),
        textScale: 1.0,
        width: 300,
      ));
      await tester.pump();

      expect(find.text('Rádio Teste'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('does not overflow/clip a long text at a large text scale', (tester) async {
      // Narrow width + long text forces the scrolling (Marquee) branch;
      // the large textScaler reproduces the exact mismatch the bug came
      // from — this is what used to clip the real, rendered text at the
      // bottom of its SizedBox.
      await tester.pumpWidget(_wrap(
        const ScrollingText(
          text: 'GFM Salvador Bahia FM 90.1 — uma estação bem grande',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        textScale: 2.0,
        width: 220,
      ));
      await tester.pump();

      // This is the actual regression check: the clipping bug threw
      // (or, on the web renderer, painted past its bounds) right here,
      // on the very first frame — before Marquee's own scroll animation
      // ever starts.
      expect(tester.takeException(), isNull);

      // Marquee starts its continuous scroll loop after `startAfter`
      // (real Duration, backed by a genuine `Timer` inside the package —
      // see its own source) and keeps going forever by design, so the
      // test can't just wait for it to settle. Advance past that delay
      // so the one real `Timer` involved fires, then unmount to dispose
      // its `ScrollController` — cleaning up before the test ends
      // without depending on the marquee package cancelling anything
      // itself, since a `Future.delayed` can't be cancelled.
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpWidget(const SizedBox());
    });
  });
}
