// A single line of text that scrolls continuously (right to left) when it
// is too wide to fit, and just sits still — centered, like any other
// `Text` — when it already fits. Used for the station name and "now
// playing" title on the home screen, which used to grow to two lines and
// wrap instead.
//
// WHY measure first instead of always scrolling: a short station name
// endlessly drifting back and forth would be motion for no reason, which
// is not just visual noise but a real readability cost for the elderly
// audience this app is built for. Scrolling only when the text genuinely
// does not fit keeps the common case (most station names) perfectly
// still, and reserves motion for the case it actually solves.
import 'package:flutter/material.dart';
import 'package:marquee/marquee.dart';

class ScrollingText extends StatelessWidget {
  final String text;
  final TextStyle style;

  const ScrollingText({super.key, required this.text, required this.style});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // WHY `textScaler` is passed explicitly: `TextPainter` measures
        // at 1x by default, ignoring the system's text-size accessibility
        // setting entirely. Without this, a person with larger text
        // enabled would get a `SizedBox` sized for the *unscaled* text
        // wrapped around a `Marquee` that renders at the *actual*,
        // larger scale (Text/Marquee always respect the ambient
        // MediaQuery scale on their own) — the mismatch clips the real,
        // taller text right at the box's edge. Matching the scaler here
        // makes the measurement (and the fits-on-one-line check just
        // below) agree with what is actually rendered, at any text size.
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          maxLines: 1,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();

        if (painter.width <= constraints.maxWidth) {
          return Text(text, style: style, maxLines: 1, overflow: TextOverflow.ellipsis);
        }

        return SizedBox(
          height: painter.height,
          child: Marquee(
            text: text,
            style: style,
            velocity: 35,
            blankSpace: 50,
            startAfter: const Duration(seconds: 1),
            pauseAfterRound: const Duration(seconds: 2),
            fadingEdgeStartFraction: 0.08,
            fadingEdgeEndFraction: 0.08,
          ),
        );
      },
    );
  }
}
