import Flutter
import UIKit
import WidgetKit

// Extends FlutterAppDelegate/FlutterImplicitEngineDelegate; Flutter's implicit
// engine setup is used as-is here.
//
// Also registers the "com.nice.radio/home_widget" channel — the native side
// of lib/services/home_widget_service.dart, mirroring
// android/.../MainActivity.kt. Two directions, both using the constants
// declared once in ios/NiceRadioWidget/WidgetShared.swift (added to this
// target's membership too — see that file's own doc):
//   - outbound (`updateNowPlaying` calls from Dart): written into the
//     App Group's shared UserDefaults, then WidgetKit is told to redraw.
//   - inbound (a widget button tap): the widget extension's AppIntents
//     can't call playback code directly — that all lives in this app's own
//     process (the just_audio/audio_service player) — so they post a Darwin
//     notification instead, which this class observes and relays into
//     Flutter as a `widgetAction` method call. This only works while this
//     app's process is actually alive; see NiceRadioWidgetIntents.swift's
//     own doc for why that's true whenever it matters (the app is playing).
@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var homeWidgetChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let messenger = engineBridge.pluginRegistry
      .registrar(forPlugin: "com.nice.radio/home_widget")!
      .messenger()
    let channel = FlutterMethodChannel(name: "com.nice.radio/home_widget", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handleHomeWidgetCall(call, result: result)
    }
    homeWidgetChannel = channel

    registerWidgetActionObservers()
  }

  private func handleHomeWidgetCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "updateNowPlaying" else {
      result(FlutterMethodNotImplemented)
      return
    }
    let args = call.arguments as? [String: Any]
    let defaults = UserDefaults(suiteName: niceRadioAppGroupId)
    defaults?.set(args?["stationName"] as? String, forKey: WidgetDefaultsKey.stationName)
    defaults?.set(args?["songTitle"] as? String, forKey: WidgetDefaultsKey.songTitle)
    defaults?.set(args?["isPlaying"] as? Bool ?? false, forKey: WidgetDefaultsKey.isPlaying)
    // `Uint8List` arguments arrive as `FlutterStandardTypedData` — `.data`
    // is the raw `Data` inside it. `UserDefaults` (unlike Android's
    // SharedPreferences) accepts `Data` directly, no base64 needed.
    let artwork = (args?["artworkPng"] as? FlutterStandardTypedData)?.data
    defaults?.set(artwork, forKey: WidgetDefaultsKey.artworkData)

    // Harmless no-op if the widget extension target doesn't exist yet (or
    // no widget is placed on a home screen) — safe to call unconditionally.
    WidgetCenter.shared.reloadAllTimelines()
    result(nil)
  }

  // Registers one observer per widget action. The C callback Darwin
  // notifications require gets no context of its own beyond the
  // notification's name — which is exactly enough here, since each
  // registration below maps one fixed name to one fixed action string, read
  // back out of `name` inside the shared callback rather than needing any
  // per-observer state.
  private func registerWidgetActionObservers() {
    let center = CFNotificationCenterGetDarwinNotifyCenter()
    let observer = Unmanaged.passUnretained(self).toOpaque()
    let callback: CFNotificationCallback = { _, observer, name, _, _ in
      guard let observer, let name else { return }
      let appDelegate = Unmanaged<AppDelegate>.fromOpaque(observer).takeUnretainedValue()
      appDelegate.handleWidgetDarwinNotification(name.rawValue as String)
    }
    for notificationName in [
      WidgetDarwinNotification.playPause,
      WidgetDarwinNotification.next,
      WidgetDarwinNotification.previous,
    ] {
      CFNotificationCenterAddObserver(
        center, observer, callback, notificationName as CFString, nil, .deliverImmediately
      )
    }
  }

  private func handleWidgetDarwinNotification(_ notificationName: String) {
    let action: String
    switch notificationName {
    case WidgetDarwinNotification.playPause: action = HomeWidgetActionName.playPause
    case WidgetDarwinNotification.next: action = HomeWidgetActionName.next
    case WidgetDarwinNotification.previous: action = HomeWidgetActionName.previous
    default: return
    }
    homeWidgetChannel?.invokeMethod("widgetAction", arguments: action)
  }
}
