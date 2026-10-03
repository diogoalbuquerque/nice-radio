// Siri, Shortcuts and Voice Control entry points (App Intents, iOS 16+).
//
// WHY this exists: lets a person run the radio without touching the screen —
// "Ei Siri, tocar Nice Radio", or a Shortcuts automation such as "every
// morning at 7, play the radio of Bahia". Each intent only *queues a
// command* on `NiceRadioCommandBridge`; the real work (picking the station,
// switching the state, playing) happens in Dart, in
// lib/providers/voice_commands_provider.dart, so Android and iOS behave
// identically. AppDelegate.swift forwards the queue to Flutter.
//
// `openAppWhenRun = true` on the intents that start playback or switch
// state: the app process must be alive to own the audio session, and
// launching it from the background is exactly what this flag does. Pausing
// and skipping don't need to open the app.
//
// Choosing a state by voice was deliberately dropped (not needed); the
// state still comes from the app's own settings.
// Phrases are Portuguese because Info.plist's development region is pt-BR.
import AppIntents
import Foundation

/// Command queue shared by every intent and AppDelegate. Dart pulls it via
/// the "com.nice.radio/commands" channel (see voice_command_service.dart
/// for why pull, not push). Main-thread only.
final class NiceRadioCommandBridge {
  static let shared = NiceRadioCommandBridge()

  /// Set by AppDelegate once the Flutter channel exists.
  var notify: (() -> Void)?
  private var pending: [[String: String]] = []

  func enqueue(_ command: [String: String]) {
    DispatchQueue.main.async {
      self.pending.append(command)
      self.notify?()
    }
  }

  func takePending() -> [[String: String]] {
    let commands = pending
    pending = []
    return commands
  }
}

/// Stations the Dart side caches (current state only, already in dial
/// order, each name like "RJ - 98,1 FM - O Dia"), so Siri can offer and
/// match them. See `VoiceCommandService.cacheStations`.
let niceRadioStationsDefaultsKey = "nice_radio_station_list"

@available(iOS 16.0, *)
struct PlayRadioIntent: AppIntent {
  static var title: LocalizedStringResource = "Tocar rádio"
  static var description = IntentDescription("Toca a última rádio que você ouviu.")
  static var openAppWhenRun: Bool = true

  func perform() async throws -> some IntentResult & ProvidesDialog {
    NiceRadioCommandBridge.shared.enqueue(["action": "play"])
    return .result(dialog: "Tocando a rádio")
  }
}

@available(iOS 16.0, *)
struct PauseRadioIntent: AppIntent {
  static var title: LocalizedStringResource = "Pausar rádio"
  static var description = IntentDescription("Pausa a rádio que está tocando.")

  func perform() async throws -> some IntentResult & ProvidesDialog {
    NiceRadioCommandBridge.shared.enqueue(["action": "pause"])
    return .result(dialog: "Rádio pausada")
  }
}

@available(iOS 16.0, *)
struct NextStationIntent: AppIntent {
  static var title: LocalizedStringResource = "Próxima estação"
  static var description = IntentDescription("Passa para a próxima estação da lista.")

  func perform() async throws -> some IntentResult & ProvidesDialog {
    NiceRadioCommandBridge.shared.enqueue(["action": "next"])
    return .result(dialog: "Próxima estação")
  }
}

@available(iOS 16.0, *)
struct PreviousStationIntent: AppIntent {
  static var title: LocalizedStringResource = "Estação anterior"
  static var description = IntentDescription("Volta para a estação anterior da lista.")

  func perform() async throws -> some IntentResult & ProvidesDialog {
    NiceRadioCommandBridge.shared.enqueue(["action": "previous"])
    return .result(dialog: "Estação anterior")
  }
}

@available(iOS 16.0, *)
struct PlayStationIntent: AppIntent {
  static var title: LocalizedStringResource = "Tocar uma estação"
  static var description = IntentDescription("Toca uma estação do seu estado, pelo nome.")
  static var openAppWhenRun: Bool = true

  @Parameter(title: "Estação", requestValueDialog: "Qual estação?")
  var station: StationEntity

  static var parameterSummary: some ParameterSummary {
    Summary("Tocar \(\.$station)")
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    NiceRadioCommandBridge.shared.enqueue(["action": "playStation", "stationId": station.id])
    return .result(dialog: "Tocando \(station.name)")
  }
}

@available(iOS 16.0, *)
struct StationEntity: AppEntity {
  static var typeDisplayRepresentation: TypeDisplayRepresentation = "Estação"
  static var defaultQuery = StationQuery()

  var id: String
  var name: String

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: "\(name)")
  }
}

@available(iOS 16.0, *)
struct StationQuery: EntityStringQuery {
  private func all() -> [StationEntity] {
    let stored = UserDefaults.standard.array(forKey: niceRadioStationsDefaultsKey) as? [[String: String]] ?? []
    return stored.compactMap { item in
      guard let id = item["id"], let name = item["name"] else { return nil }
      return StationEntity(id: id, name: name)
    }
  }

  func entities(for identifiers: [String]) async throws -> [StationEntity] {
    all().filter { identifiers.contains($0.id) }
  }

  func entities(matching string: String) async throws -> [StationEntity] {
    let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
    return all().filter { $0.name.range(of: string, options: options) != nil }
  }

  func suggestedEntities() async throws -> [StationEntity] {
    all()
  }
}

@available(iOS 16.0, *)
struct NiceRadioShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: PlayRadioIntent(),
      phrases: [
        "Tocar \(.applicationName)",
        "Ligar \(.applicationName)",
        "Tocar a rádio no \(.applicationName)",
      ],
      shortTitle: "Tocar rádio",
      systemImageName: "play.circle.fill"
    )
    AppShortcut(
      intent: PauseRadioIntent(),
      phrases: [
        "Pausar \(.applicationName)",
        "Parar \(.applicationName)",
        "Desligar \(.applicationName)",
        "Pausar a rádio no \(.applicationName)",
      ],
      shortTitle: "Pausar rádio",
      systemImageName: "pause.circle.fill"
    )
    AppShortcut(
      intent: NextStationIntent(),
      phrases: [
        "Próxima estação no \(.applicationName)",
        "Trocar de estação no \(.applicationName)",
      ],
      shortTitle: "Próxima estação",
      systemImageName: "forward.circle.fill"
    )
    AppShortcut(
      intent: PreviousStationIntent(),
      phrases: ["Estação anterior no \(.applicationName)"],
      shortTitle: "Estação anterior",
      systemImageName: "backward.circle.fill"
    )
    AppShortcut(
      intent: PlayStationIntent(),
      phrases: ["Tocar \(\.$station) no \(.applicationName)"],
      shortTitle: "Tocar uma estação",
      systemImageName: "dot.radiowaves.left.and.right"
    )
  }
}
