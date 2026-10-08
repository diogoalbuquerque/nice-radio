package com.nice.radio

import android.content.Intent
import android.os.Bundle
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
//
// And the "com.nice.radio/commands" channel (lib/services/
// voice_command_service.dart): launcher shortcuts and Google Assistant App
// Actions open this activity with a niceradio:// URI. Commands are queued
// here and Dart *pulls* them (takePendingCommands) — a cold start delivers
// the intent before Dart is listening, so pushing the payload would lose it.
class MainActivity : AudioServiceActivity() {
    private var commandChannel: MethodChannel? = null
    private val pendingCommands = mutableListOf<Map<String, String>>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Not on a recreation (savedInstanceState != null): Android hands
        // back the original launch intent, which would replay an old
        // "pause" or "next".
        if (savedInstanceState == null) {
            enqueueCommand(intent)
            // Also ping: a launcher shortcut (CLEAR_TASK) recreates this
            // activity while the Flutter engine (shared with audio_service)
            // is still alive, so Dart will not run its startup drain again.
            // On a true cold start nobody is listening yet and the ping is
            // a harmless no-op; Dart's startup drain picks the command up.
            commandChannel?.invokeMethod("commandAvailable", null)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        enqueueCommand(intent)
        commandChannel?.invokeMethod("commandAvailable", null)
    }

    private fun enqueueCommand(intent: Intent?) {
        if (intent == null || (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) != 0) return
        val uri = intent.data ?: return
        if (uri.scheme != "niceradio") return
        pendingCommands.add(mapOf("uri" to uri.toString()))
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        commandChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.nice.radio/commands").also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method == "takePendingCommands") {
                    result.success(pendingCommands.toList())
                    pendingCommands.clear()
                } else {
                    result.notImplemented()
                }
            }
        }
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
