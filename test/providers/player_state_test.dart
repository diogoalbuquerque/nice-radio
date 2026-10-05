import 'package:flutter_test/flutter_test.dart';
import 'package:nice_radio/providers/player_state.dart';

void main() {
  const initial = PlayerState.initial();

  test('copyWith keeps nullable fields when omitted and clears them with null', () {
    final withTexts = initial.copyWith(nowPlayingTitle: 'Música', errorMessage: 'Erro');

    expect(withTexts.copyWith(volumePercent: 20).nowPlayingTitle, 'Música');
    expect(withTexts.copyWith(volumePercent: 20).errorMessage, 'Erro');

    final cleared = withTexts.copyWith(nowPlayingTitle: null, errorMessage: null);
    expect(cleared.nowPlayingTitle, isNull);
    expect(cleared.errorMessage, isNull);
  });

  test('speaker starts off so Bluetooth/car audio is never hijacked at launch', () {
    expect(initial.speakerOn, isFalse);
  });

  group('remainingSleepMinutes', () {
    final now = DateTime(2026, 1, 1, 22);

    test('rounds up so the last partial minute still shows 1', () {
      expect(remainingSleepMinutes(now.add(const Duration(minutes: 30)), now), 30);
      expect(remainingSleepMinutes(now.add(const Duration(minutes: 29, seconds: 1)), now), 30);
      expect(remainingSleepMinutes(now.add(const Duration(seconds: 1)), now), 1);
    });

    test('is 0 once the time has passed', () {
      expect(remainingSleepMinutes(now, now), 0);
      expect(remainingSleepMinutes(now.subtract(const Duration(minutes: 5)), now), 0);
    });
  });
}
