import AppIntents
import SwiftUI
import UIKit
import WidgetKit

struct NiceRadioWidgetEntry: TimelineEntry {
  let date: Date
  let stationName: String
  let songTitle: String?
  let isPlaying: Bool
  let artworkData: Data?
}

// A single-entry, externally-triggered timeline — no periodic refresh of
// its own. AppDelegate.swift calls `WidgetCenter.shared.reloadAllTimelines()`
// every time real playback state changes (see its `handleHomeWidgetCall`),
// which is what actually keeps this widget current; a time-based refresh
// policy would either lag behind real changes or poll for no reason, since
// nothing shown here changes on a schedule.
struct NiceRadioTimelineProvider: TimelineProvider {
  func placeholder(in context: Context) -> NiceRadioWidgetEntry {
    NiceRadioWidgetEntry(date: Date(), stationName: "Nice Radio", songTitle: nil, isPlaying: false, artworkData: nil)
  }

  func getSnapshot(in context: Context, completion: @escaping (NiceRadioWidgetEntry) -> Void) {
    completion(currentEntry())
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<NiceRadioWidgetEntry>) -> Void) {
    completion(Timeline(entries: [currentEntry()], policy: .never))
  }

  private func currentEntry() -> NiceRadioWidgetEntry {
    let defaults = UserDefaults(suiteName: niceRadioAppGroupId)
    return NiceRadioWidgetEntry(
      date: Date(),
      stationName: defaults?.string(forKey: WidgetDefaultsKey.stationName) ?? "Nice Radio",
      songTitle: defaults?.string(forKey: WidgetDefaultsKey.songTitle),
      isPlaying: defaults?.bool(forKey: WidgetDefaultsKey.isPlaying) ?? false,
      artworkData: defaults?.data(forKey: WidgetDefaultsKey.artworkData)
    )
  }
}

// The app's own blue/salmon brand colors (these exact values come from the app icon's
// background blue and its "n" mark's salmon), hardcoded here rather than
// pulled from Flutter's AppColors: a widget extension is a separate Swift
// module with no access to Dart constants, so these are kept in sync by
// hand — the same "manual sync" caveat Android's own copy already has in
// widget_colors.xml. Salmon has no dark-mode variant, on either platform:
// it is a fixed brand accent, not a light/dark-adaptive UI color.
private extension Color {
  static let niceRadioPrimaryLight = Color(red: 0x1E / 255, green: 0x5C / 255, blue: 0x8C / 255)
  static let niceRadioPrimaryDark = Color(red: 0x6A / 255, green: 0xA9 / 255, blue: 0xDE / 255)
  static let niceRadioSalmon = Color(red: 0xE8 / 255, green: 0x79 / 255, blue: 0x5C / 255)
}

// Static text, not scrolling — WidgetKit's SwiftUI views have no
// general-purpose marquee/auto-scroll primitive the way the in-app
// ScrollingText widget does (see lib/widgets/scrolling_text.dart), and
// faking one with a timer would need per-frame timeline entries, which
// WidgetKit explicitly budgets against (a handful of reloads per hour, not
// per second). A long name just truncates with "…" (`.lineLimit(1)`'s
// default truncation) — the "static text with '…'" approach agreed for
// both platforms' widgets, matching Android's own
// `android:ellipsize="end"` in nice_radio_widget.xml.
struct NiceRadioWidgetView: View {
  var entry: NiceRadioTimelineProvider.Entry
  @Environment(\.colorScheme) private var colorScheme

  private var primaryColor: Color {
    colorScheme == .dark ? .niceRadioPrimaryDark : .niceRadioPrimaryLight
  }

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      logoView
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

      VStack(alignment: .leading, spacing: 2) {
        Text(entry.stationName)
          .font(.headline)
          .lineLimit(1)
          .truncationMode(.tail)
        if let songTitle = entry.songTitle, !songTitle.isEmpty {
          Text(songTitle)
            .font(.caption)
            .foregroundColor(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
        }
        Spacer(minLength: 4)
        // Filled blue circle behind play/pause, matching the in-app play
        // button (_PlaybackControls' Material circle in home_screen.dart)
        // and Android's own widget_play_pause_bg — by explicit request, so
        // this button reads as this app's primary action. Salmon on
        // prev/next echoes the app icon's own accent, since this widget
        // sits right next to that icon on the home screen — same reasoning
        // as Android's widget_salmon color.
        HStack {
          Button(intent: PreviousStationIntent()) {
            Image(systemName: "backward.fill")
          }
          .foregroundColor(.niceRadioSalmon)
          Spacer()
          Button(intent: PlayPauseIntent()) {
            Image(systemName: entry.isPlaying ? "pause.fill" : "play.fill")
              .font(.title2)
              .foregroundColor(.white)
              .frame(width: 40, height: 40)
              .background(Circle().fill(primaryColor))
          }
          Spacer()
          Button(intent: NextStationIntent()) {
            Image(systemName: "forward.fill")
          }
          .foregroundColor(.niceRadioSalmon)
        }
        .buttonStyle(.plain)
        .font(.title3)
      }
    }
    .padding()
    .containerBackground(.background, for: .widget)
  }

  // The station's real favicon (as raw image data pushed over from Dart —
  // see AppDelegate.swift's `handleHomeWidgetCall`) when there is one;
  // otherwise a generated initials box (see StationArtworkService), or —
  // only in the brief window before the very first update ever arrives —
  // a plain placeholder glyph.
  @ViewBuilder
  private var logoView: some View {
    if let data = entry.artworkData, let uiImage = UIImage(data: data) {
      Image(uiImage: uiImage)
        .resizable()
        .aspectRatio(contentMode: .fill)
    } else {
      ZStack {
        RoundedRectangle(cornerRadius: 10, style: .continuous).fill(primaryColor.opacity(0.15))
        Image(systemName: "antenna.radiowaves.left.and.right")
          .foregroundColor(primaryColor)
      }
    }
  }
}

// WHY `.systemMedium` only, not also `.systemSmall`/`.systemLarge`: matches
// the single size Android's widget offers (see
// android/app/src/main/res/xml/nice_radio_widget_info.xml's
// targetCellWidth/targetCellHeight) — a small widget has no real room for
// a logo box, two lines of text and three buttons without cramming, and a
// large one would just be the same content with wasted space. Supporting
// only one, deliberately-chosen size on both platforms is simpler than a
// second layout that would rarely get used.
//
// WHY `Button(intent:)` (interactive widgets) rather than `Link` +
// deep-link, which also works on older iOS: a `Link` always foregrounds
// the app to handle the tap — exactly the "open the app just to press
// play" friction this whole feature exists to remove (see Android's
// MediaButtonReceiver routing for the same goal on that platform).
// Interactive buttons that run an `AppIntent` in place, without opening
// anything, need iOS 17+ — set this extension target's own minimum
// deployment to 17.0 (it can be higher than the main Runner target's).
struct NiceRadioWidget: Widget {
  let kind: String = "NiceRadioWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: NiceRadioTimelineProvider()) { entry in
      NiceRadioWidgetView(entry: entry)
    }
    .configurationDisplayName("Nice Radio")
    .description("Rádio atual, com play/pause e trocar de estação.")
    .supportedFamilies([.systemMedium])
  }
}
