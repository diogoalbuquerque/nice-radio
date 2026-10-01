package com.nice.radio

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.util.Base64
import android.view.KeyEvent
import android.view.View
import android.widget.RemoteViews
import com.ryanheise.audioservice.MediaButtonReceiver

/**
 * Home-screen widget: a station logo box, station name, a static song-title
 * line, and prev/play-pause/next — see nice_radio_widget.xml for the layout.
 *
 * WHY the buttons target audio_service's own [MediaButtonReceiver]
 * directly, via [Intent.ACTION_MEDIA_BUTTON], instead of talking to this
 * app's Dart code at all: that receiver is already exactly what a
 * Bluetooth headset or the lock-screen notification's buttons send
 * events to — audio_service's `MediaSessionCallback` (a plain
 * `MediaSessionCompat.Callback`) decodes `KEYCODE_MEDIA_PLAY_PAUSE`/
 * `_NEXT`/`_PREVIOUS` into calls on `RadioAudioHandler` automatically
 * (see player_provider.dart/audio_player_handler.dart). Reusing that
 * path means the widget controls playback exactly like every other
 * remote control this app already supports — no new Dart-side plumbing,
 * and it works the same way whether Flutter's own engine/UI is currently
 * active or not, the same as a headset button press already does.
 */
class NiceRadioWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        for (appWidgetId in appWidgetIds) {
            updateWidget(context, appWidgetManager, appWidgetId)
        }
    }

    companion object {
        private const val PREFS_NAME = "com.nice.radio.widget"
        private const val KEY_STATION_NAME = "station_name"
        private const val KEY_SONG_TITLE = "song_title"
        private const val KEY_IS_PLAYING = "is_playing"
        private const val KEY_ARTWORK_BASE64 = "artwork_base64"

        /**
         * Called from [MainActivity]'s "com.nice.radio/home_widget" channel
         * handler every time PlayerNotifier's station/title/play-state
         * changes. Persists the data (so a freshly-placed widget, or one
         * redrawn after a device reboot before the app itself has run
         * again, still has something real to show instead of nothing) and
         * redraws every placed instance of this widget.
         *
         * [artworkPng] is the station's logo — its real favicon, or a
         * generated initials image when it has none — as raw PNG bytes
         * from StationArtworkService (see home_widget_service.dart). It is
         * base64-encoded for storage because SharedPreferences has no
         * binary-blob type, only primitives/strings; `null` (or a decode
         * failure later) falls back to the launcher icon in [updateWidget].
         */
        fun updateNowPlaying(
            context: Context,
            stationName: String,
            songTitle: String?,
            isPlaying: Boolean,
            artworkPng: ByteArray?,
        ) {
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
                .putString(KEY_STATION_NAME, stationName)
                .putString(KEY_SONG_TITLE, songTitle)
                .putBoolean(KEY_IS_PLAYING, isPlaying)
                .putString(KEY_ARTWORK_BASE64, artworkPng?.let { Base64.encodeToString(it, Base64.NO_WRAP) })
                .apply()

            val appWidgetManager = AppWidgetManager.getInstance(context)
            val ids = appWidgetManager.getAppWidgetIds(ComponentName(context, NiceRadioWidgetProvider::class.java))
            for (id in ids) {
                updateWidget(context, appWidgetManager, id)
            }
        }

        private fun updateWidget(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val stationName = prefs.getString(KEY_STATION_NAME, null)
            val songTitle = prefs.getString(KEY_SONG_TITLE, null)
            val isPlaying = prefs.getBoolean(KEY_IS_PLAYING, false)
            val artworkBase64 = prefs.getString(KEY_ARTWORK_BASE64, null)

            val views = RemoteViews(context.packageName, R.layout.nice_radio_widget)

            if (stationName.isNullOrEmpty()) {
                views.setTextViewText(R.id.widget_station_name, "Nice Radio")
                views.setViewVisibility(R.id.widget_song_title, View.GONE)
            } else {
                views.setTextViewText(R.id.widget_station_name, stationName)
                if (songTitle.isNullOrEmpty()) {
                    views.setViewVisibility(R.id.widget_song_title, View.GONE)
                } else {
                    views.setTextViewText(R.id.widget_song_title, songTitle)
                    views.setViewVisibility(R.id.widget_song_title, View.VISIBLE)
                }
            }

            val artworkBitmap = artworkBase64?.let {
                try {
                    val bytes = Base64.decode(it, Base64.NO_WRAP)
                    BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                } catch (e: Exception) {
                    null
                }
            }
            if (artworkBitmap != null) {
                views.setImageViewBitmap(R.id.widget_station_logo, artworkBitmap)
            } else {
                // No station picked yet (fresh install) or artwork
                // generation genuinely failed — the launcher icon is a
                // reasonable, always-available stand-in either way.
                views.setImageViewResource(R.id.widget_station_logo, R.mipmap.ic_launcher)
            }

            views.setImageViewResource(
                R.id.widget_play_pause,
                if (isPlaying) R.drawable.widget_pause else R.drawable.widget_play,
            )
            views.setContentDescription(
                R.id.widget_play_pause,
                if (isPlaying) "Pausar" else "Tocar",
            )

            views.setOnClickPendingIntent(
                R.id.widget_previous,
                mediaButtonPendingIntent(context, KeyEvent.KEYCODE_MEDIA_PREVIOUS),
            )
            views.setOnClickPendingIntent(
                R.id.widget_play_pause,
                mediaButtonPendingIntent(context, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE),
            )
            views.setOnClickPendingIntent(
                R.id.widget_next,
                mediaButtonPendingIntent(context, KeyEvent.KEYCODE_MEDIA_NEXT),
            )

            // Tapping the rest of the widget (station name/song title, not
            // one of the three control buttons) opens the app — the same
            // "tap the body to open, tap a control to act" split most
            // media widgets use.
            val openAppIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            val openAppPendingIntent = PendingIntent.getActivity(
                context,
                0,
                openAppIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            views.setOnClickPendingIntent(R.id.widget_root, openAppPendingIntent)

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }

        /**
         * Builds a broadcast [PendingIntent] that looks exactly like a
         * hardware media-button press — see the class doc for why this is
         * the whole integration. [keyCode] is one of the `KeyEvent
         * .KEYCODE_MEDIA_*` constants; using it as the [PendingIntent]'s
         * request code keeps the three buttons' PendingIntents distinct
         * from one another (otherwise Android would treat them as the
         * "same" intent and only the most recently created one would
         * actually fire).
         */
        private fun mediaButtonPendingIntent(context: Context, keyCode: Int): PendingIntent {
            val intent = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
                setClass(context, MediaButtonReceiver::class.java)
                putExtra(Intent.EXTRA_KEY_EVENT, KeyEvent(KeyEvent.ACTION_DOWN, keyCode))
            }
            return PendingIntent.getBroadcast(
                context,
                keyCode,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
    }
}
