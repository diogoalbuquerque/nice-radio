// iOS only: pauses the radio when another app starts a *mixing* audio use
// (e.g. WhatsApp recording a voice note) and resumes it afterwards — but only
// if this class did the pausing.
//
// Android: notification sounds ask for a "may duck" focus and the system
// lowers our volume by itself (like YouTube Music;
// `androidWillPauseWhenDucked` is false in `AudioRoutingService`) — pausing on
// `duck` made every notification stop the radio. A WhatsApp voice note asks for
// the same focus, so focus can't tell them apart; instead `MainActivity.kt`
// reports when another app is *recording the microphone* (this app never does)
// over `com.nice.radio/recording`, and that pauses us.
//
// iOS: WhatsApp records in `playAndRecord` with mixing, so no interruption
//   ever arrives; the only signal is the "silence secondary audio" hint.
import 'dart:async';
import 'dart:io' show Platform;

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

class AudioInterruptionPauser {
  final AudioPlayer _player;
  StreamSubscription<AVAudioSessionSilenceSecondaryAudioHintType>? _silenceHintSubscription;
  bool _pausedByUs = false;
  bool _disposed = false;

  StreamSubscription<bool>? _requestsSubscription;
  final Stream<bool>? _requests;

  /// [requests] (`true` = another app wants silence) replaces the platform
  /// signals; for tests.
  // ignore: prefer_initializing_formals
  AudioInterruptionPauser(this._player, {Stream<bool>? requests}) : _requests = requests;

  Future<void> start() async {
    if (_disposed) return;
    if (_requests != null) {
      _requestsSubscription = _requests.listen(_onSilenceRequested);
      return;
    }
    if (!kIsWeb && Platform.isAndroid) {
      const channel = MethodChannel('com.nice.radio/recording');
      channel.setMethodCallHandler((call) async {
        if (call.method == 'recordingChanged') _onSilenceRequested(call.arguments as bool);
      });
    }
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
    _requestsSubscription?.cancel();
    if (!kIsWeb && Platform.isAndroid) {
      const MethodChannel('com.nice.radio/recording').setMethodCallHandler(null);
    }
  }
}
