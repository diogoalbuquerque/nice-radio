import AppIntents
import Foundation

// Runs inside the widget extension process when its own button is tapped —
// see WidgetShared.swift's doc for why this can't call playback code
// directly and posts a Darwin notification instead, and AppDelegate.swift
// for the app-side half of that bridge.
//
// WHY this only works while Nice Radio's own process is alive: iOS keeps a
// backgrounded app fully suspended almost immediately — except for a
// handful of documented background modes, one of which this app already
// declares for playback itself (`UIBackgroundModes: audio`, see Info.plist).
// So exactly when these buttons matter (a station is actually playing), the
// app process is genuinely running, not suspended, and receives the Darwin
// notification immediately. If the app was fully force-quit (not just
// backgrounded), there is no process to receive it — tapping a widget
// button then does nothing, the same real limitation most iOS widgets that
// control an already-running player have; there is no "wake the app
// silently" capability a Darwin notification can grant it doesn't already
// have.
private func postWidgetAction(_ name: String) {
  CFNotificationCenterPostNotification(
    CFNotificationCenterGetDarwinNotifyCenter(),
    CFNotificationName(name as CFString),
    nil, nil, true
  )
}

struct PlayPauseIntent: AppIntent {
  static var title: LocalizedStringResource = "Tocar ou pausar"

  func perform() async throws -> some IntentResult {
    postWidgetAction(WidgetDarwinNotification.playPause)
    return .result()
  }
}

struct NextStationIntent: AppIntent {
  static var title: LocalizedStringResource = "Próxima estação"

  func perform() async throws -> some IntentResult {
    postWidgetAction(WidgetDarwinNotification.next)
    return .result()
  }
}

struct PreviousStationIntent: AppIntent {
  static var title: LocalizedStringResource = "Estação anterior"

  func perform() async throws -> some IntentResult {
    postWidgetAction(WidgetDarwinNotification.previous)
    return .result()
  }
}
