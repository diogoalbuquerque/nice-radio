package com.nice.radio

import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Extends AudioServiceActivity (itself a thin FlutterActivity subclass)
// instead of FlutterActivity directly — this is what lets audio_service
// share this activity's Flutter engine with its background playback
// service, so the same running app instance shows the lock-screen/
// notification controls.
//
// Also registers the "com.nice.radio/home_widget" channel — the native
// side of lib/services/home_widget_service.dart — which pushes the
// current station/song/play-state, plus a station-logo image (its real
// favicon or a generated initials box — see StationArtworkService), into
// the home-screen widget's own storage and redraws it. See
// NiceRadioWidgetProvider.kt for the rest of this and why the widget's own
// buttons never need to come back through here at all.
class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.nice.radio/home_widget")
            .setMethodCallHandler { call, result ->
                if (call.method == "updateNowPlaying") {
                    NiceRadioWidgetProvider.updateNowPlaying(
                        this,
                        call.argument<String>("stationName") ?: "",
                        call.argument<String>("songTitle"),
                        call.argument<Boolean>("isPlaying") ?: false,
                        call.argument<ByteArray>("artworkPng"),
                    )
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }
}
