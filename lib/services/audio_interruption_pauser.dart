// Pauses the radio when another app starts a *mixing* audio use (e.g.
// WhatsApp playing or recording a voice note) and resumes it afterwards —
// but only if this class did the pausing.
//
// Why it exists: `just_audio` only handles `pause`/`unknown` interruptions;
// for `duck` it lowers volume only when the usage is `game`, so with this
// app's `media` usage a duck was a silent no-op. A volume duck was rejected
// on purpose: player gain is fixed at 1.0 (loudness = system volume), and a
// missed "ended" event would leave it stuck quiet, while a missed resume just
// leaves the radio paused like any other pause.
//
// Per platform:
// - Android: `AudioSessionConfiguration.androidWillPauseWhenDucked` (set in
//   `AudioRoutingService`) stops the system from auto-ducking and delivers a
//   `duck` event instead.
// - iOS: WhatsApp records in `playAndRecord` with mixing, so no interruption
//   ever arrives; the only signal is the "silence secondary audio" hint.
import 'dart:async';
import 'dart:io' show Platform;

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:just_audio/just_audio.dart';

class AudioInterruptionPauser {
  final AudioPlayer _player;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSubscription;
  StreamSubscription<AVAudioSessionSilenceSecondaryAudioHintType>? _silenceHintSubscription;
  bool _pausedByUs = false;
  bool _disposed = false;

  AudioInterruptionPauser(this._player);

  Future<void> start() async {
    final session = await AudioSession.instance;
    if (_disposed) return;
    _interruptionSubscription = session.interruptionEventStream.listen((event) {
      if (event.type != AudioInterruptionType.duck) return;
      _onSilenceRequested(event.begin);
    });
    if (!kIsWeb && Platform.isIOS) {
      _silenceHintSubscription = AVAudioSession().silenceSecondaryAudioHintStream.listen(
            (type) => _onSilenceRequested(type == AVAudioSessionSilenceSecondaryAudioHintType.begin),
          );
    }
  }

  void _onSilenceRequested(bool begin) {
    if (begin) {
      if (_player.playing) {
        _pausedByUs = true;
        _player.pause();
      }
    } else if (_pausedByUs) {
      _pausedByUs = false;
      _player.play();
    }
  }

  void dispose() {
    _disposed = true;
    _interruptionSubscription?.cancel();
    _silenceHintSubscription?.cancel();
  }
}
