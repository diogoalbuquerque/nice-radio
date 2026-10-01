// Design tokens for the whole app: colors, text styles and the ThemeData
// used by MaterialApp.
//
// WHY a single file for this: every screen and widget reads colors from
// here instead of writing hex codes inline. If the color scheme needs to
// change again (like it did once already, from green to blue+orange), it
// is a one-file edit instead of a hunt across every screen.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// All colors used in the app.
///
/// WHY blue + orange instead of the more common green "success" accent:
/// the target audience includes people with color blindness and cataracts.
/// Green is one of the hardest colors to distinguish for red-green color
/// blindness (the most common form), and pastel colors lose contrast
/// under the haziness caused by cataracts. Blue + orange is the classic
/// color-blind-safe pairing (distinguishable across protanopia,
/// deuteranopia and tritanopia), and every shade below is kept dark and
/// saturated on purpose: contrast (light vs. dark), not hue, is what
/// still reads clearly through a clouded lens. This holds in both the
/// light and dark palettes below — "modo noturno" only inverts which end
/// of the light/dark scale is the background, never the hues themselves.
///
/// IMPORTANT: color is never the *only* signal for state in this app
/// (e.g. a favorited station also gets a filled star icon, not just a
/// color change) — that is deliberate, not an oversight, so do not
/// "simplify" a widget by removing the icon/text and keeping only color.
///
/// WHY these are getters that branch on [_brightness], not plain
/// `static const` values: this app now has a "modo noturno" toggle (see
/// `SettingsNotifier.toggleDarkMode`), and every screen already reads
/// colors as bare `AppColors.xxx` — turning that into a context-aware
/// lookup
/// (`Theme.of(context).extension<...>()`) would have meant touching
/// every call site across every screen and widget file. A getter that
/// reads one static flag keeps that exact call-site API working
/// unchanged, and [setBrightness] is the one seam that updates it — see
/// its own doc for who calls it and why call sites do not need to.
class AppColors {
  AppColors._();

  static Brightness _brightness = Brightness.light;
  static bool get _isDark => _brightness == Brightness.dark;

  /// Sets which palette the getters below resolve to. Called by
  /// `buildAppTheme` (see below), which `NiceRadioApp.build()` (in
  /// `main.dart`) calls at the very top of every rebuild, before any
  /// descendant widget's own `build()` runs — so by the time any screen
  /// reads `AppColors.card` (etc.) in the same frame, this has already
  /// been updated to match the persisted "modo noturno" setting. Screens
  /// do not need to call this themselves, and should not — it is
  /// app-wide, not per-widget.
  static void setBrightness(Brightness brightness) {
    _brightness = brightness;
  }

  static Color get background => _isDark ? const Color(0xFF13171C) : const Color(0xFFFAF7F2);
  static Color get card => _isDark ? const Color(0xFF1C222A) : const Color(0xFFFFFFFF);
  static Color get border => _isDark ? const Color(0xFF333B46) : const Color(0xFFE4DDD0);
  static Color get textPrimary => _isDark ? const Color(0xFFF2F0EA) : const Color(0xFF211F1C);
  static Color get textSecondary => _isDark ? const Color(0xFFAEA99F) : const Color(0xFF6B6459);

  /// Primary accent: used for the play button, active tabs, selected
  /// states and links. Kept dark/saturated for contrast in light mode;
  /// brightened (not just "the same blue on a dark background", which
  /// would read too dim) so it keeps the same contrast job at night.
  static Color get primary => _isDark ? const Color(0xFF6AA9DE) : const Color(0xFF1E5C8C);
  static Color get primaryTint => _isDark ? const Color(0xFF1E3349) : const Color(0xFFE3EDF5);

  /// Secondary accent, reserved for the favorite ("star") affordance only.
  /// Orange never competes with blue for meaning elsewhere in the UI —
  /// including in "modo noturno": the new lamp/flashlight toggle (see
  /// `home_screen.dart`) deliberately stays neutral, not orange, so this
  /// still holds.
  static Color get favorite => _isDark ? const Color(0xFFE0AC4E) : const Color(0xFFC48A2E);
  static Color get favoriteTint => _isDark ? const Color(0xFF3A2E16) : const Color(0xFFFBF1DE);
  static Color get favoriteBorder => _isDark ? const Color(0xFF8A6A34) : const Color(0xFFE9C878);
  static Color get favoriteText => _isDark ? const Color(0xFFEFC377) : const Color(0xFF8A621E);

  static Color get chipBackground => _isDark ? const Color(0xFF262D36) : const Color(0xFFEFE9DD);
  static Color get subtleBackground => _isDark ? const Color(0xFF1A2028) : const Color(0xFFF4F0E6);

  /// Deterministic fallback avatars for stations without a usable favicon.
  ///
  /// WHY a fixed palette instead of a random/generated color: two reasons.
  /// First, accessibility — every entry here was hand-picked to avoid
  /// green (see the class doc) and to stay dark enough for white text on
  /// top to remain readable. Second, determinism — the same station must
  /// always get the same color across app runs, which a random color
  /// would not guarantee. See [RadioStation.avatarColor] for how a
  /// station is mapped onto this list.
  ///
  /// WHY this one stays a plain `static const`, unlike everything above:
  /// these are already dark, saturated colors designed for white text on
  /// top — they read fine on both a light and a dark scaffold background,
  /// so there is no light/dark variant to switch between.
  static const List<Color> avatarPalette = [
    Color(0xFFB4622E), // terracotta / orange
    Color(0xFF3F6485), // blue
    Color(0xFF54447A), // purple
    Color(0xFF8B4747), // maroon
    Color(0xFF2E4A66), // navy
    Color(0xFF7A5230), // brown
    Color(0xFF8A621E), // amber-brown
    Color(0xFF9C5B1F), // rust
  ];
}

/// Builds the app's [ThemeData] for the given [brightness].
///
/// WHY Atkinson Hyperlegible: it is a typeface designed by the Braille
/// Institute specifically to stay legible for readers with low vision —
/// a direct fit for an app aimed at elderly users. It ships through
/// Google Fonts, so `google_fonts` downloads and caches it on first use
/// instead of us bundling font files by hand.
///
/// WHY "modo noturno" is a manual toggle, never automatic (not tied to
/// the system's own light/dark setting): dark mode is a genuine net
/// positive for some low-vision conditions (less glare, easier on light
/// sensitivity) but can be a net *negative* for others — light text on a
/// dark background is known to be harder to read through some forms of
/// cataracts, an effect called halation, where bright text on a dark
/// background appears to "bloom" and blur at the edges. Given the
/// crossover audience here, guessing from the system setting risked
/// silently making the app harder to read for exactly the people it is
/// built for. An explicit, reversible toggle (see the lamp/flashlight
/// icon in `home_screen.dart`) lets each person decide for themselves,
/// same reasoning as this app never forcing "Viva-voz" either.
ThemeData buildAppTheme(Brightness brightness) {
  // Must happen before anything below reads AppColors.* — see
  // AppColors.setBrightness's own doc for why this is the one call site
  // that needs to, and why nothing else does.
  AppColors.setBrightness(brightness);

  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: brightness,
    ),
  );

  final textTheme = GoogleFonts.atkinsonHyperlegibleTextTheme(
    base.textTheme,
  ).apply(
    bodyColor: AppColors.textPrimary,
    displayColor: AppColors.textPrimary,
  );

  return base.copyWith(
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
    ),
    // Every tappable control in this app targets at least 48x48 logical
    // pixels (see individual widgets). This just raises the *default*
    // Material tap target floor to match, for anything that doesn't
    // set an explicit size.
    materialTapTargetSize: MaterialTapTargetSize.padded,
  );
}
