// Shown once, on the very first launch: explains the app in one line and
// asks for location permission, which is how we find the user's state
// without ever asking them to type anything.
//
// WHY there is always a visible "Agora não" (skip) option: location
// permission can be denied, the device can have location services off,
// or the user may simply not want to grant it. None of those should be a
// dead end — skipping just lands on the home screen's "choose your state
// manually" prompt, the same fallback used when automatic detection
// fails after being granted. See LocationService and HomeScreen's
// `NoStateSelected` (in `lib/widgets/`) for the rest of that path.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/settings_provider.dart';
import '../services/analytics_service.dart';
import '../services/location_service.dart';
import '../theme/app_theme.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  bool _isResolvingLocation = false;

  @override
  void initState() {
    super.initState();
    // OnboardingScreen is never a pushed route either — same reasoning
    // as HomeScreen's own `initState` call in `home_screen.dart`.
    ref.read(analyticsServiceProvider).logScreenView('onboarding');
  }

  Future<void> _requestLocationAndContinue() async {
    setState(() => _isResolvingLocation = true);

    final stateName = await LocationService().resolveBrazilianState();
    if (stateName != null) {
      await ref.read(settingsProvider.notifier).selectState(stateName);
    }

    await _finishOnboarding();
  }

  Future<void> _skip() => _finishOnboarding();

  // WHY this doesn't navigate: see main.dart's `_StartupGate` doc — a
  // `Navigator` push here used to discard the wrapper widgets above it
  // (the home-screen widget sync, the iOS resume fix, the quick-action
  // shortcut sync), silently breaking all three for the rest of the
  // session. Marking the provider done instead just lets `_StartupGate`
  // swap to `HomeScreen` as a plain, in-place rebuild.
  Future<void> _finishOnboarding() {
    return ref.read(onboardingDoneProvider.notifier).markDone();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // The app's actual launcher icon, not a generic Material
              // icon — same reasoning as the home screen's header logo
              // (see HomeScreen's _HomeContent).
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Image.asset('assets/icon/icon.png', width: 72, height: 72),
              ),
              const SizedBox(height: 20),
              const Text(
                'Nice Radio',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'Que tal ouvir as rádios locais em poucos toques? Ative '
                'sua localização para encontrarmos as estações do seu '
                'estado e comece a favoritar suas preferidas.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 17, height: 1.5, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                  ),
                  onPressed: _isResolvingLocation ? null : _requestLocationAndContinue,
                  child: _isResolvingLocation
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                        )
                      : const Text('Permitir localização', style: TextStyle(fontSize: 17)),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _isResolvingLocation ? null : _skip,
                child: Text(
                  'Agora não, escolher depois',
                  style: TextStyle(fontSize: 15, color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
