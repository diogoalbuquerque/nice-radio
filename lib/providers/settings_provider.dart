// App-wide settings that must survive an app restart: which state the
// user is browsing, and the data-usage counter. Both are persisted
// through [StorageService] on every change.
//
// WHY AsyncNotifier instead of a plain Notifier: reading the saved values
// from disk (SharedPreferences) is inherently asynchronous. AsyncNotifier
// models that honestly — the UI sees an [AsyncValue] and can show a brief
// loading state on cold start — instead of us faking a synchronous
// default and silently overwriting it a moment later, which is a common
// source of a visible "flash" of wrong content on app start.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/analytics_service.dart';
import '../services/storage_service.dart';

/// Shared instance of [StorageService]. WHY a provider for a plain class
/// with no state of its own: so tests can override it with a fake/mock
/// storage implementation without touching real SharedPreferences.
final storageServiceProvider = Provider<StorageService>((ref) {
  return StorageService();
});

class AppSettings {
  final String? selectedState;
  final int dataUsedBytes;
  final DateTime dataUsedSince;
  final bool darkModeEnabled;
  final bool suppressOfflineWarning;

  const AppSettings({
    required this.selectedState,
    required this.dataUsedBytes,
    required this.dataUsedSince,
    required this.darkModeEnabled,
    required this.suppressOfflineWarning,
  });

  AppSettings copyWith({
    String? selectedState,
    int? dataUsedBytes,
    DateTime? dataUsedSince,
    bool? darkModeEnabled,
    bool? suppressOfflineWarning,
  }) {
    return AppSettings(
      selectedState: selectedState ?? this.selectedState,
      dataUsedBytes: dataUsedBytes ?? this.dataUsedBytes,
      dataUsedSince: dataUsedSince ?? this.dataUsedSince,
      darkModeEnabled: darkModeEnabled ?? this.darkModeEnabled,
      suppressOfflineWarning: suppressOfflineWarning ?? this.suppressOfflineWarning,
    );
  }
}

class SettingsNotifier extends AsyncNotifier<AppSettings> {
  StorageService get _storage => ref.read(storageServiceProvider);

  @override
  Future<AppSettings> build() async {
    return AppSettings(
      selectedState: await _storage.getSelectedState(),
      dataUsedBytes: await _storage.getDataUsedBytes(),
      dataUsedSince: await _storage.getDataUsedSince(),
      darkModeEnabled: await _storage.getDarkModeEnabled(),
      suppressOfflineWarning: await _storage.getSuppressOfflineWarning(),
    );
  }

  Future<void> selectState(String stateName) async {
    await _storage.setSelectedState(stateName);
    final current = state.value;
    if (current != null) {
      state = AsyncData(current.copyWith(selectedState: stateName));
    }
    // Single choke point both the automatic GPS-resolved guess
    // (OnboardingScreen) and a manual pick (SettingsScreen) already go
    // through — one call here covers "which state is most selected" for
    // both, without either screen needing to know about analytics.
    ref.read(analyticsServiceProvider).logStateSelected(stateName);
  }

  /// Adds [bytes] to the running data-usage counter. Called by
  /// [PlayerNotifier] roughly every few seconds while a station is
  /// playing — see that file for how the byte count itself is estimated.
  Future<void> addDataUsage(int bytes) async {
    final current = state.value;
    if (current == null || bytes <= 0) return;
    final updated = current.dataUsedBytes + bytes;
    await _storage.setDataUsedBytes(updated);
    state = AsyncData(current.copyWith(dataUsedBytes: updated));
  }

  Future<void> toggleDarkMode() async {
    final current = state.value;
    if (current == null) return;
    final enabled = !current.darkModeEnabled;
    await _storage.setDarkModeEnabled(enabled);
    state = AsyncData(current.copyWith(darkModeEnabled: enabled));
  }

  /// Sets (not toggles) the "Não mostrar novamente" preference from the
  /// stations-offline dialog's own checkbox — see
  /// `StorageService.getSuppressOfflineWarning` for the full WHY. An
  /// explicit setter rather than a toggle because the dialog always knows
  /// the exact value it wants (the checkbox's final state when
  /// dismissed), not "the opposite of whatever it currently is".
  Future<void> setSuppressOfflineWarning(bool suppress) async {
    await _storage.setSuppressOfflineWarning(suppress);
    final current = state.value;
    if (current != null) {
      state = AsyncData(current.copyWith(suppressOfflineWarning: suppress));
    }
  }

  Future<void> resetDataUsage() async {
    final now = DateTime.now();
    await _storage.setDataUsedBytes(0);
    await _storage.setDataUsedSince(now);
    final current = state.value;
    if (current != null) {
      state = AsyncData(current.copyWith(dataUsedBytes: 0, dataUsedSince: now));
    }
  }
}

final settingsProvider = AsyncNotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);

/// Whether onboarding (the first-launch location prompt) is done —
/// persisted via [StorageService.getOnboardingDone]/`setOnboardingDone`.
///
/// WHY this is a reactive provider `main.dart`'s `_StartupGate` watches,
/// instead of `OnboardingScreen` just calling `Navigator.push` to
/// `HomeScreen` once it finishes: see `_StartupGate`'s own doc in
/// `main.dart` for the real bug that approach caused — pushing a new
/// route discarded every wrapper widget above `_StartupGate`, silently
/// breaking their `ref.listen`/`WidgetsBindingObserver` registrations
/// for the rest of that session. `OnboardingScreen.markDone` is the only
/// writer.
class OnboardingNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() {
    return ref.read(storageServiceProvider).getOnboardingDone();
  }

  Future<void> markDone() async {
    await ref.read(storageServiceProvider).setOnboardingDone(true);
    state = const AsyncData(true);
  }
}

final onboardingDoneProvider = AsyncNotifierProvider<OnboardingNotifier, bool>(
  OnboardingNotifier.new,
);
