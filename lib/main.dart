// App entry point: Firebase setup, the root `MaterialApp`, and the
// onboarding-vs-home gate. Platform wrappers live in `app/platform_sync.dart`.
import 'dart:ui' show PlatformDispatcher;

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/platform_sync.dart';
import 'firebase_options.dart';
import 'providers/settings_provider.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase is Android/iOS only: `firebase_options.dart` has no web entry and
  // Crashlytics ships no web implementation (web is a dev convenience).
  if (!kIsWeb) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

    // Both hooks are needed for complete crash reports: errors Flutter itself
    // catches, and raw async/platform-channel errors outside its zone.
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  }

  runApp(const ProviderScope(child: NiceRadioApp()));
}

class NiceRadioApp extends ConsumerWidget {
  const NiceRadioApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // `select`: rebuild the whole app only when "modo noturno" flips, not on
    // every settings change (the data-usage counter ticks while playing).
    final darkModeEnabled = ref.watch(
      settingsProvider.select((async) => async.value?.darkModeEnabled ?? false),
    );

    return MaterialApp(
      title: 'Nice Radio',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(darkModeEnabled ? Brightness.dark : Brightness.light),
      // Auto-logs `screen_view` for pushed routes — **only for routes that
      // carry a name**: the observer skips a null `RouteSettings.name`, so every
      // `MaterialPageRoute` must be pushed with
      // `settings: RouteSettings(name: ...)`. Home and Onboarding are not
      // pushed routes (see `_StartupGate`) and log their own `screen_view`.
      //
      // `Firebase.apps.isEmpty` (not `kIsWeb`) is the right guard: it also
      // covers `flutter test`, which never runs `main()`.
      navigatorObservers: Firebase.apps.isEmpty
          ? const []
          : [FirebaseAnalyticsObserver(analytics: FirebaseAnalytics.instance)],
      home: const AppLifecycleSync(
        child: HomeWidgetSync(child: QuickActionsSync(child: _StartupGate())),
      ),
    );
  }
}

/// Onboarding on first launch, home afterwards. Reacts to
/// [onboardingDoneProvider] instead of pushing a route: the sync wrappers sit
/// in this same route, and replacing it destroyed their `State` (see
/// `app/platform_sync.dart`).
class _StartupGate extends ConsumerWidget {
  const _StartupGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onboardingDone = ref.watch(onboardingDoneProvider);
    return onboardingDone.when(
      data: (done) => done ? const HomeScreen() : const OnboardingScreen(),
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      // An unreadable flag shows onboarding (it has a skip button) rather than
      // assuming it was done.
      error: (_, _) => const OnboardingScreen(),
    );
  }
}
