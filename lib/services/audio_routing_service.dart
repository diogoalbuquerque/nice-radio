// Audio-session setup and output routing (phone speaker vs. connected
// device). Stateless: callers pass what to apply. Platform-only, so it has no
// unit tests (it talks to `audio_session`'s platform channels).
//
// Speaker forcing is automatic, never a user toggle: the phone speaker is
// forced only when nothing external (wired/Bluetooth/car/USB/HDMI) is
// connected; otherwise the phone routes normally. Mechanism per platform:
// - Android: `setSpeakerphoneOn` and `setCommunicationDevice` are call-audio
//   APIs that only act for the app holding `MODE_IN_COMMUNICATION`, and media
//   playback stays in `MODE_NORMAL` (both alone were tried on a real phone
//   with a wired headset and did nothing). So forcing switches the mode first
//   and restores `normal` when off. Accepted trade-off: a brief glitch at the
//   switch and possible effects on other apps' audio focus.
// - iOS: `overrideOutputAudioPort` only works under `playAndRecord`, so that
//   category is used only while forced (plain `playback` otherwise), with
//   `allowBluetoothA2dp` to keep stereo A2DP. It is a *recording* category,
//   hence `NSMicrophoneUsageDescription` in Info.plist (omitting it crashes
//   the app); the app never records.
import 'dart:io' show Platform;

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:just_audio/just_audio.dart';

class AudioRoutingService {
  const AudioRoutingService();

  /// (Re)applies the media session category and the speaker override.
  Future<void> configureSession({required bool forceSpeaker}) async {
    final session = await AudioSession.instance;
    // `willPauseWhenDucked` stops Android from auto-ducking our volume; we get
    // a `duck` event instead and pause (see `AudioInterruptionPauser`).
    final musicConfig = const AudioSessionConfiguration.music().copyWith(androidWillPauseWhenDucked: true);

    if (!kIsWeb && Platform.isIOS && forceSpeaker) {
      await session.configure(musicConfig.copyWith(
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        avAudioSessionCategoryOptions:
            AVAudioSessionCategoryOptions.defaultToSpeaker | AVAudioSessionCategoryOptions.allowBluetoothA2dp,
      ));
    } else {
      await session.configure(musicConfig);
    }

    if (!kIsWeb && Platform.isIOS) {
      await AVAudioSession().overrideOutputAudioPort(
        forceSpeaker ? AVAudioSessionPortOverride.speaker : AVAudioSessionPortOverride.none,
      );
    }
    if (!kIsWeb && Platform.isAndroid) {
      await _setAndroidForcedSpeaker(forceSpeaker);
    }
  }

  /// Whether the phone speaker should be forced right now: `true` when only
  /// built-in outputs are connected. `null` when it cannot be told (web, or
  /// the query failed) — callers then leave the current routing alone.
  Future<bool?> shouldForceSpeaker() async {
    if (kIsWeb) return null;
    try {
      final session = await AudioSession.instance;
      final devices = await session.getDevices(includeInputs: false, includeOutputs: true);
      // `AudioDeviceType` is experimental upstream but the only classification
      // audio_session 0.2.4 offers.
      bool isBuiltIn(AudioDevice device) =>
          // ignore: experimental_member_use
          device.type == AudioDeviceType.builtInSpeaker || device.type == AudioDeviceType.builtInEarpiece;
      return devices.every(isBuiltIn);
    } catch (_) {
      return null;
    }
  }

  /// Re-asserts the category and reactivates the session. iOS can stop
  /// treating the app as Now Playing without interrupting audio (lock-screen
  /// controls vanish after resume + relock); `configure()` alone never
  /// activates, so `setActive(true)` is a separate, required call.
  Future<void> reactivateSession({required bool forceSpeaker}) async {
    await configureSession(forceSpeaker: forceSpeaker);
    final session = await AudioSession.instance;
    await session.setActive(true);
  }

  /// Sets the Android audio attributes explicitly and awaited. `just_audio`'s
  /// automatic version is disabled (`androidApplyAudioAttributes: false`)
  /// because its activation can overlap this app's `setUrl()` and silently
  /// cancel it with `PlayerInterruptedException: Loading interrupted` (seen on
  /// a cold start via the quick action). Awaiting this before `setUrl` makes
  /// the two activations sequential. No-ops when unchanged.
  Future<void> applyAndroidAudioAttributes(AudioPlayer player) {
    return player.setAndroidAudioAttributes(const AndroidAudioAttributes(
      contentType: AndroidAudioContentType.music,
      usage: AndroidAudioUsage.media,
    ));
  }

  Future<void> _setAndroidForcedSpeaker(bool forceSpeaker) async {
    final manager = AndroidAudioManager();
    if (forceSpeaker) {
      await manager.setMode(AndroidAudioHardwareMode.inCommunication);
      await manager.setSpeakerphoneOn(true);
      try {
        final devices = await manager.getAvailableCommunicationDevices();
        for (final device in devices) {
          if (device.type == AndroidAudioDeviceType.builtInSpeaker) {
            await manager.setCommunicationDevice(device);
            break;
          }
        }
      } catch (_) {
        // API 31+ only; on older devices `setSpeakerphoneOn` carries it.
      }
    } else {
      try {
        await manager.clearCommunicationDevice();
      } catch (_) {
        // API < 31: nothing was set, nothing to clear.
      }
      await manager.setSpeakerphoneOn(false);
      await manager.setMode(AndroidAudioHardwareMode.normal); // never stay in call-like mode
    }
  }
}
