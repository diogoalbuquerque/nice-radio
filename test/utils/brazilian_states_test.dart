// BrazilianStates.normalize is the one thing standing between "whatever
// text a reverse-geocoding service felt like returning" and a Radio
// Browser API query — a wrong or missed match here silently shows the
// user the wrong (or no) state, so its edge cases are worth pinning down.
import 'package:flutter_test/flutter_test.dart';
import 'package:nice_radio/utils/brazilian_states.dart';

void main() {
  group('BrazilianStates.normalize', () {
    test('matches the canonical name exactly', () {
      expect(BrazilianStates.normalize('São Paulo'), 'São Paulo');
    });

    test('matches an abbreviation', () {
      expect(BrazilianStates.normalize('SP'), 'São Paulo');
      expect(BrazilianStates.normalize('rj'), 'Rio de Janeiro');
    });

    test('is accent-insensitive', () {
      expect(BrazilianStates.normalize('Sao Paulo'), 'São Paulo');
      expect(BrazilianStates.normalize('SAO PAULO'), 'São Paulo');
    });

    test('is case-insensitive', () {
      expect(BrazilianStates.normalize('são paulo'), 'São Paulo');
    });

    test('tolerates surrounding whitespace', () {
      expect(BrazilianStates.normalize('  São Paulo  '), 'São Paulo');
    });

    test('returns null for text that does not match any state', () {
      expect(BrazilianStates.normalize('Not A Real Place'), isNull);
    });

    test('returns null for null or empty input', () {
      expect(BrazilianStates.normalize(null), isNull);
      expect(BrazilianStates.normalize(''), isNull);
      expect(BrazilianStates.normalize('   '), isNull);
    });

    test(
      'does not loosely match a state name as a substring of something '
      'else — a wrong match here would silently show the wrong state\'s '
      'radio stations',
      () {
        expect(BrazilianStates.normalize('São Paulo, Brazil'), isNull);
      },
    );

    test('all 27 states are present with distinct abbreviations', () {
      expect(BrazilianStates.all, hasLength(27));
      final abbreviations = BrazilianStates.all.map((s) => s.abbreviation).toSet();
      expect(abbreviations, hasLength(27));
    });
  });
}
