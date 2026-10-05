// The About sheet is reached from Settings' version row; this checks that
// it opens as a bottom sheet and carries the content the owner asked for
// (what the app is, safe/no ads).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nice_radio/widgets/about_sheet.dart';

void main() {
  testWidgets('shows description and safety promise', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(onPressed: () => showAboutSheet(context), child: const Text('abrir')),
          ),
        ),
      ),
    );

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    expect(find.text('Nice Radio'), findsOneWidget);
    expect(find.text('Principais funções'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Seguro e sem propagandas'), 200);
    expect(find.text('Seguro e sem propagandas'), findsOneWidget);
  });
}
