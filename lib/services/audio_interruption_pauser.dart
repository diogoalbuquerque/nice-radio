// iOS only: pauses the radio when another app starts a *mixing* audio use
// (e.g. WhatsApp recording a voice note) and resumes it afterwards — but only
// if this class did the pausing.
//
// Android is deliberately NOT handled here: notification sounds ask for a
// "may duck" focus and the system lowers our volume by itself (like YouTube
// Music; `androidWillPauseWhenDucked` is false in `AudioRoutingService`).
// Pausing on those `duck` events made every notification stop the radio.
//
// iOS: WhatsApp records in `playAndRecord` with mixing, so no interruption
//   ever arrives; the only signal is the "silence secondary audio" hint.
import 'dart:async';
import 'dart:io' show Platform;

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:just_audio/just_audio.dart';

class AudioInterruptionPauser {
  final AudioPlayer _player;
  StreamSubscription<AVAudioSessionSilenceSecondaryAudioHintType>? _silenceHintSubscription;
  bool _pausedByUs = false;
  bool _disposed = false;

  AudioInterruptionPauser(this._player);

  Future<void> start() async {
    if (_disposed) return;
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
    _silenceHintSubscription?.cancel();
  }
}
