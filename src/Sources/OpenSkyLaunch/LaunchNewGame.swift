// What a new game at a chosen place starts with: the hour, the weather, the story
// state, the race menu, and the starting items. The launcher and `openskycli game
// debug newgame` both give these as text, so the text forms live here.

public import Foundation
public import OpenSkyGameData

/// The state of the main story when the new game starts.
nonisolated public enum LaunchStory: String, CaseIterable, Sendable {
    /// The opening quest does not run.
    case notStarted = "not-started"
    /// The opening is done and the player left Helgen with Hadvar.
    case helgenHadvar = "helgen-hadvar"
    /// The opening is done and the player left Helgen with Ralof.
    case helgenRalof = "helgen-ralof"

    public var title: String {
        switch self {
        case .notStarted: "Not started"
        case .helgenHadvar: "Helgen done, with Hadvar"
        case .helgenRalof: "Helgen done, with Ralof"
        }
    }
}

nonisolated public struct LaunchStartingItem: Equatable, Sendable {
    public let editorID: String
    public let count: Int32
    public let equips: Bool

    init(_ editorID: String, count: Int32 = 1, equips: Bool = false) {
        self.editorID = editorID
        self.count = count
        self.equips = equips
    }
}

/// A set of items the player gets at the start. The editor IDs are those of
/// `Skyrim.esm`; an item the load order lacks is skipped with a notification.
nonisolated public enum LaunchItemPreset: String, CaseIterable, Sendable {
    case none
    case warrior
    case archer
    case mage
    case thief

    public var title: String {
        switch self {
        case .none: "None"
        case .warrior: "Warrior: iron armour, sword, and shield"
        case .archer: "Archer: leather armour, bow, and arrows"
        case .mage: "Mage: robes, spell tomes, and potions"
        case .thief: "Thief: leather armour, dagger, and lockpicks"
        }
    }

    public var items: [LaunchStartingItem] {
        switch self {
        case .none:
            []
        case .warrior:
            [
                .init("ArmorIronCuirass", equips: true), .init("ArmorIronBoots", equips: true),
                .init("ArmorIronGauntlets", equips: true), .init("ArmorIronHelmet", equips: true),
                .init("ArmorIronShield", equips: true), .init("IronSword", equips: true)
            ] + Self.supplies
        case .archer:
            Self.leatherArmour + [
                .init("IronArrow", count: 100, equips: true), .init("HuntingBow", equips: true),
                .init("IronDagger")
            ] + Self.supplies
        case .mage:
            [
                .init("ClothesRobesMageNoviceTemplate", equips: true), .init(
                    "ClothesMGBoots",
                    equips: true
                ),
                .init("SpellTomeFlames"), .init("SpellTomeSparks"), .init("SpellTomeHealing"),
                .init("SpellTomeOakflesh"), .init("RestoreMagicka01", count: 5)
            ] + Self.supplies
        case .thief:
            Self.leatherArmour + [
                .init("IronDagger", equips: true), .init("Lockpick", count: 30)
            ] + Self.supplies
        }
    }

    private static let leatherArmour: [LaunchStartingItem] = [
        .init("ArmorLeatherCuirass", equips: true), .init("ArmorLeatherBoots", equips: true),
        .init("ArmorLeatherGauntlets", equips: true), .init("ArmorLeatherHelmet", equips: true)
    ]

    private static let supplies: [LaunchStartingItem] = [
        .init("RestoreHealth01", count: 5), .init("Torch01", count: 2),
        .init("Gold001", count: 500)
    ]
}

nonisolated public struct LaunchNewGame: Equatable, Sendable {
    public static let hourRange: ClosedRange<Float> = 0 ... 24

    public var start: LaunchStart
    /// The hour of the day; nil keeps the hour a new game starts at.
    public var hour: Float?
    /// The hour as the game clock takes it: 24 is the same hour as 0.
    public var clockHour: Float? {
        hour.map { $0.truncatingRemainder(dividingBy: Self.hourRange.upperBound) }
    }

    /// A weather editor ID to force; nil leaves the weather to the game.
    public var weather: String?
    public var story: LaunchStory
    public var opensRaceMenu: Bool
    public var items: LaunchItemPreset

    public init(
        start: LaunchStart, hour: Float? = nil, weather: String? = nil,
        story: LaunchStory = .notStarted, opensRaceMenu: Bool = true,
        items: LaunchItemPreset = .none
    ) {
        self.start = start
        self.hour = hour
        self.weather = weather
        self.story = story
        self.opensRaceMenu = opensRaceMenu
        self.items = items
    }
}

/// The options as text, before validation.
nonisolated public struct LaunchNewGameText: Equatable, Sendable {
    public var start: String
    public var hour: String
    public var weather: String
    public var story: String
    public var items: String
    public var opensRaceMenu: Bool

    public init(
        start: String, hour: String = "", weather: String = "",
        story: String = LaunchStory.notStarted.rawValue,
        items: String = LaunchItemPreset.none.rawValue, opensRaceMenu: Bool = true
    ) {
        self.start = start
        self.hour = hour
        self.weather = weather
        self.story = story
        self.items = items
        self.opensRaceMenu = opensRaceMenu
    }

    public init(_ game: LaunchNewGame) {
        self.init(
            start: game.start.storedValue,
            hour: game.hour.map { String($0) } ?? "",
            weather: game.weather ?? "",
            story: game.story.rawValue,
            items: game.items.rawValue,
            opensRaceMenu: game.opensRaceMenu
        )
    }

    /// The new game, or the one-line reason the text cannot be used.
    public func validate() -> Result<LaunchNewGame, LaunchNewGameProblem> {
        guard let start = LaunchStart(storedValue: start), start != .normal else {
            return .failure(.badStart(start))
        }
        guard let story = LaunchStory(rawValue: story) else { return .failure(.badStory) }
        guard let items = LaunchItemPreset(rawValue: items) else { return .failure(.badItems) }
        switch Self.hour(from: hour) {
        case let .failure(problem):
            return .failure(problem)
        case let .success(hour):
            let weather = weather.trimmingCharacters(in: .whitespaces)
            guard weather.isEmpty || LaunchStartForm.isEditorID(weather) else {
                return .failure(.badWeather)
            }
            return .success(LaunchNewGame(
                start: start, hour: hour, weather: weather.isEmpty ? nil : weather,
                story: story, opensRaceMenu: opensRaceMenu, items: items
            ))
        }
    }

    /// Empty text keeps the hour of a new game.
    public static func hour(from text: String) -> Result<Float?, LaunchNewGameProblem> {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return .success(nil) }
        guard let hour = Float(trimmed), LaunchNewGame.hourRange.contains(hour) else {
            return .failure(.badHour)
        }
        return .success(hour)
    }
}

nonisolated public enum LaunchNewGameProblem: Error, Equatable, Sendable {
    case badStart(String)
    case badHour
    case badWeather
    case badStory
    case badItems

    public var reason: String {
        switch self {
        case let .badStart(text):
            "'\(text)' is not a start; use cell:EditorID, exterior:Worldspace:X:Y, "
                + "or marker:Worldspace:Plugin:ObjectID"
        case .badHour:
            "The hour must be a number from 0 to 24, such as 13.5"
        case .badWeather:
            "A weather editor ID has only letters, digits, and underscores"
        case .badStory:
            "The story is one of: "
                + LaunchStory.allCases.map(\.rawValue).joined(separator: ", ")
        case .badItems:
            "The items are one of: "
                + LaunchItemPreset.allCases.map(\.rawValue).joined(separator: ", ")
        }
    }
}

nonisolated extension LaunchPreferences {
    public static let hourSetting = SettingKey("OpenSkyLaunchNewGameHour", default: "")
    public static let weatherSetting = SettingKey("OpenSkyLaunchNewGameWeather", default: "")
    public static let storySetting = SettingKey(
        "OpenSkyLaunchNewGameStory", default: LaunchStory.notStarted.rawValue
    )
    public static let itemsSetting = SettingKey(
        "OpenSkyLaunchNewGameItems", default: LaunchItemPreset.none.rawValue
    )
    public static let raceMenuSetting = SettingKey("OpenSkyLaunchNewGameRaceMenu", default: true)

    /// The saved options as text. The start is the saved start.
    public static func savedNewGameText(
        userDefaults: UserDefaults = GameDataLocator.settingsDefaults
    ) -> LaunchNewGameText {
        let store = SettingsStore(defaults: userDefaults)
        return LaunchNewGameText(
            start: savedStart(userDefaults: userDefaults).storedValue,
            hour: store.value(hourSetting),
            weather: store.value(weatherSetting),
            story: store.value(storySetting),
            items: store.value(itemsSetting),
            opensRaceMenu: store.value(raceMenuSetting)
        )
    }

    /// The new game Play starts at `start`; a saved option that no longer reads
    /// falls back to its default.
    public static func savedNewGame(
        at start: LaunchStart, userDefaults: UserDefaults = GameDataLocator.settingsDefaults
    ) -> LaunchNewGame {
        let text = savedNewGameText(userDefaults: userDefaults)
        // A saved hour that no longer parses keeps the hour of the game.
        let hour: Float? = switch LaunchNewGameText.hour(from: text.hour) {
        case let .success(value): value
        case .failure: nil
        }
        return LaunchNewGame(
            start: start,
            hour: hour,
            weather: LaunchStartForm.isEditorID(text.weather) ? text.weather : nil,
            story: LaunchStory(rawValue: text.story) ?? .notStarted,
            opensRaceMenu: text.opensRaceMenu,
            items: LaunchItemPreset(rawValue: text.items) ?? .none
        )
    }

    /// Saves every option but the start, which `remember(_:)` saves.
    public static func remember(
        options text: LaunchNewGameText,
        userDefaults: UserDefaults = GameDataLocator.settingsDefaults
    ) {
        let store = SettingsStore(defaults: userDefaults)
        store.set(text.hour, for: hourSetting)
        store.set(text.weather, for: weatherSetting)
        store.set(text.story, for: storySetting)
        store.set(text.items, for: itemsSetting)
        store.set(text.opensRaceMenu, for: raceMenuSetting)
    }
}
