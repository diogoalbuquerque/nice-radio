// A minimal smoke test: on a fresh install (no SharedPreferences data yet)
// the app must land on the onboarding screen, not crash on startup.
//
// This replaces the default `flutter create` counter-app test, which
// referenced widgets this project does not have.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nice_radio/main.dart';

void main() {
  testWidgets('Shows onboarding on first launch', (WidgetTester tester) async {
    // SharedPreferences needs its test-only in-memory backend seeded
    // before StorageService (which every provider here depends on,
    // directly or indirectly) tries to read from it.
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const ProviderScope(child: NiceRadioApp()));
    await tester.pumpAndSettle();

    expect(find.text('Nice Radio'), findsWidgets);
    expect(find.text('Permitir localização'), findsOneWidget);
  });
}
