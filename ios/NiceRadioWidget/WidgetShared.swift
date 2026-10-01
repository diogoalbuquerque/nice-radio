// Shared between the Runner app target and the NiceRadioWidget extension
// target — the App Group id, the shared UserDefaults keys the app writes
// and the widget reads, and the Darwin notification names the widget posts
// and the app observes. Declaring these once, in a file added to BOTH
// targets' Target Membership (see the file inspector's "Target Membership"
// checkboxes on the right in Xcode), is what keeps the two sides of this
// bridge from silently drifting apart — see AppDelegate.swift and
// NiceRadioWidgetIntents.swift, the two places that actually use these.
import Foundation

// Must match exactly the App Group entered in both targets'
// Signing & Capabilities → App Groups, and Runner.entitlements.
public let niceRadioAppGroupId = "group.com.nice.radio.widget"

// Mirrors Android's NiceRadioWidgetProvider.kt SharedPreferences keys
// (station_name/song_title/is_playing) so both platforms' native widget
// code follow the same shape.
public enum WidgetDefaultsKey {
  public static let stationName = "station_name"
  public static let songTitle = "song_title"
  public static let isPlaying = "is_playing"
  // The station's logo — its real favicon, or a generated initials image
  // when it has none (see StationArtworkService in home_widget_service.dart)
  // — as raw PNG data. Stored directly as `Data`, unlike Android's
  // SharedPreferences copy of this same value, which has to base64-encode
  // it first: `UserDefaults` (unlike SharedPreferences) accepts `Data`
  // natively.
  public static let artworkData = "artwork_data"
}

// Darwin notifications are the only IPC available between a widget
// extension process and its host app process — they carry no payload, just
// a name, which is enough here since each button is its own fixed action.
public enum WidgetDarwinNotification {
  public static let playPause = "com.nice.radio.widgetAction.playPause"
  public static let next = "com.nice.radio.widgetAction.next"
  public static let previous = "com.nice.radio.widgetAction.previous"
}

// The action names relayed to Dart via the "com.nice.radio/home_widget"
// channel's `widgetAction` call — must match
// lib/services/home_widget_service.dart's `HomeWidgetAction` constants
// exactly (playPause/next/previous), same as Android's own copy of this
// mapping in MainActivity.kt/main.dart.
public enum HomeWidgetActionName {
  public static let playPause = "playPause"
  public static let next = "next"
  public static let previous = "previous"
}
