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
// The 27-state enum below mirrors lib/utils/brazilian_states.dart (raw
// values are the canonical names Dart expects) — keep them in sync.
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

/// Station names the Dart side caches (current state only), so Siri can
/// offer and match them. See `VoiceCommandService.cacheStations`.
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
struct ChooseStateIntent: AppIntent {
  static var title: LocalizedStringResource = "Escolher estado"
  static var description = IntentDescription("Escolhe o estado cujas rádios aparecem no aplicativo.")
  static var openAppWhenRun: Bool = true

  @Parameter(title: "Estado", requestValueDialog: "Qual estado?")
  var state: BrazilianStateOption

  static var parameterSummary: some ParameterSummary {
    Summary("Escolher o estado \(\.$state)")
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    NiceRadioCommandBridge.shared.enqueue(["action": "chooseState", "state": state.rawValue])
    return .result(dialog: "Estado escolhido: \(state.rawValue)")
  }
}

@available(iOS 16.0, *)
struct PlayStateRadioIntent: AppIntent {
  static var title: LocalizedStringResource = "Tocar rádio de um estado"
  static var description = IntentDescription("Troca para o estado escolhido e já começa a tocar uma rádio dele.")
  static var openAppWhenRun: Bool = true

  @Parameter(title: "Estado", requestValueDialog: "De qual estado?")
  var state: BrazilianStateOption

  static var parameterSummary: some ParameterSummary {
    Summary("Tocar uma rádio de \(\.$state)")
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    NiceRadioCommandBridge.shared.enqueue(["action": "playState", "state": state.rawValue])
    return .result(dialog: "Tocando uma rádio de \(state.rawValue)")
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
    NiceRadioCommandBridge.shared.enqueue(["action": "playStation", "station": station.name])
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
enum BrazilianStateOption: String, AppEnum {
  case acre = "Acre"
  case alagoas = "Alagoas"
  case amapa = "Amapá"
  case amazonas = "Amazonas"
  case bahia = "Bahia"
  case ceara = "Ceará"
  case distritoFederal = "Distrito Federal"
  case espiritoSanto = "Espírito Santo"
  case goias = "Goiás"
  case maranhao = "Maranhão"
  case matoGrosso = "Mato Grosso"
  case matoGrossoDoSul = "Mato Grosso do Sul"
  case minasGerais = "Minas Gerais"
  case para = "Pará"
  case paraiba = "Paraíba"
  case parana = "Paraná"
  case pernambuco = "Pernambuco"
  case piaui = "Piauí"
  case rioDeJaneiro = "Rio de Janeiro"
  case rioGrandeDoNorte = "Rio Grande do Norte"
  case rioGrandeDoSul = "Rio Grande do Sul"
  case rondonia = "Rondônia"
  case roraima = "Roraima"
  case santaCatarina = "Santa Catarina"
  case saoPaulo = "São Paulo"
  case sergipe = "Sergipe"
  case tocantins = "Tocantins"

  static var typeDisplayRepresentation: TypeDisplayRepresentation = "Estado"
  static var caseDisplayRepresentations: [BrazilianStateOption: DisplayRepresentation] = [
    .acre: "Acre",
    .alagoas: "Alagoas",
    .amapa: "Amapá",
    .amazonas: "Amazonas",
    .bahia: "Bahia",
    .ceara: "Ceará",
    .distritoFederal: "Distrito Federal",
    .espiritoSanto: "Espírito Santo",
    .goias: "Goiás",
    .maranhao: "Maranhão",
    .matoGrosso: "Mato Grosso",
    .matoGrossoDoSul: "Mato Grosso do Sul",
    .minasGerais: "Minas Gerais",
    .para: "Pará",
    .paraiba: "Paraíba",
    .parana: "Paraná",
    .pernambuco: "Pernambuco",
    .piaui: "Piauí",
    .rioDeJaneiro: "Rio de Janeiro",
    .rioGrandeDoNorte: "Rio Grande do Norte",
    .rioGrandeDoSul: "Rio Grande do Sul",
    .rondonia: "Rondônia",
    .roraima: "Roraima",
    .santaCatarina: "Santa Catarina",
    .saoPaulo: "São Paulo",
    .sergipe: "Sergipe",
    .tocantins: "Tocantins",
  ]
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
      intent: PlayStateRadioIntent(),
      phrases: [
        "Tocar rádio de \(\.$state) no \(.applicationName)",
        "Tocar uma rádio de \(\.$state) no \(.applicationName)",
      ],
      shortTitle: "Tocar rádio de um estado",
      systemImageName: "mappin.circle.fill"
    )
    AppShortcut(
      intent: ChooseStateIntent(),
      phrases: [
        "Escolher o estado \(\.$state) no \(.applicationName)",
        "Mudar para \(\.$state) no \(.applicationName)",
      ],
      shortTitle: "Escolher estado",
      systemImageName: "map.fill"
    )
    AppShortcut(
      intent: PlayStationIntent(),
      phrases: ["Tocar \(\.$station) no \(.applicationName)"],
      shortTitle: "Tocar uma estação",
      systemImageName: "dot.radiowaves.left.and.right"
    )
  }
}
