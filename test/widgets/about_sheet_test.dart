// The About sheet is reached from Settings' version row; this checks that
// it opens as a bottom sheet and carries the content the owner asked for
// (what the app is, safe/no ads, who made it, link to the repository).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nice_radio/widgets/about_sheet.dart';

void main() {
  testWidgets('shows description, safety promise, author and GitHub link', (tester) async {
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
    await tester.scrollUntilVisible(find.text('Diogo Albuquerque'), 200);
    expect(find.text('Diogo Albuquerque'), findsOneWidget);
    expect(find.text('Ver código no GitHub'), findsOneWidget);
    expect(niceRadioRepositoryUrl, 'https://github.com/diogoalbuquerque/nice-radio');
  });
}
