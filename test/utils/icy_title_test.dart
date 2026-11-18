import 'package:flutter_test/flutter_test.dart';
import 'package:nice_radio/utils/icy_title.dart';

void main() {
  test('blank or absent title is null', () {
    expect(freshIcyTitle(null), isNull);
    expect(freshIcyTitle('   '), isNull);
  });

  test('trims a real title', () {
    expect(freshIcyTitle('  Song  '), 'Song');
  });

  test('title left over from the previous station is ignored', () {
    expect(freshIcyTitle('FM O DIA', stale: 'FM O DIA'), isNull);
  });

  test('a different title after the switch is shown', () {
    expect(freshIcyTitle('Nova música', stale: 'FM O DIA'), 'Nova música');
  });
}
