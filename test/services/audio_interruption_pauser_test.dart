import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:nice_radio/services/audio_interruption_pauser.dart';

class _FakePlayer extends Fake implements AudioPlayer {
  @override
  bool playing = false;
  int plays = 0;

  @override
  Future<void> play() async {
    playing = true;
    plays++;
  }

  @override
  Future<void> pause() async => playing = false;
}

void main() {
  late _FakePlayer player;
  late StreamController<bool> requests;
  late AudioInterruptionPauser pauser;

  setUp(() async {
    player = _FakePlayer();
    requests = StreamController<bool>();
    pauser = AudioInterruptionPauser(player, requests: requests.stream);
    await pauser.start();
  });

  tearDown(() => pauser.dispose());

  test('pauses while another app records and resumes afterwards', () async {
    player.playing = true;
    requests.add(true);
    await Future<void>.delayed(Duration.zero);
    expect(player.playing, isFalse);

    requests.add(false);
    await Future<void>.delayed(Duration.zero);
    expect(player.playing, isTrue);
  });

  test('does not resume what the user had paused', () async {
    requests.add(true);
    requests.add(false);
    await Future<void>.delayed(Duration.zero);
    expect(player.plays, 0);
  });
}
