// What one benchmark run asks for. The launcher, the app's `--benchmark` flag,
// and the agent control command all build this one value.

import Foundation
import OpenSkyGameData

nonisolated public enum BenchmarkRequestError: Error, Equatable, CustomStringConvertible {
    case unknownScene(String)
    case unknownSetting(String)
    case badSettingValue(id: String, value: String)
    case malformed(String)

    public var description: String {
        switch self {
        case let .unknownScene(id):
            "no benchmark scene '\(id)'; known: "
                + BenchmarkTour.scenes.map(\.id).joined(separator: ", ")
        case let .unknownSetting(id):
            "no player setting '\(id)'"
        case let .badSettingValue(id, value):
            "setting '\(id)' does not take '\(value)'"
        case let .malformed(text):
            "malformed benchmark request: \(text)"
        }
    }
}

nonisolated public struct BenchmarkRequest: Codable, Equatable, Sendable {
    public var preset: BenchmarkPreset
    /// Scene ids to run instead of the preset's list.
    public var sceneIDs: [String]?
    public var overlay: Bool
    /// The run directory; nil writes into the app's own benchmark folder.
    public var outDirectory: String?
    /// A scene whose first measured frame is saved as a Metal GPU trace.
    public var captureScene: String?
    /// Player setting overrides by id, for this run only.
    public var settings: [String: Double]
    public var quitWhenDone: Bool
    /// The cold and warm load of the first scene's cells, before the tour.
    public var loadPasses: Bool
    /// Saves the window at the start, middle, and end of each shot.
    public var screenshots: Bool
    /// The game window fills the screen for the run and comes back after it.
    public var fullScreen: Bool

    public init(
        preset: BenchmarkPreset = .standard, sceneIDs: [String]? = nil, overlay: Bool = true,
        outDirectory: String? = nil, captureScene: String? = nil,
        settings: [String: Double] = [:], quitWhenDone: Bool = false, loadPasses: Bool = true,
        screenshots: Bool = false, fullScreen: Bool = true
    ) {
        self.preset = preset
        self.sceneIDs = sceneIDs
        self.overlay = overlay
        self.outDirectory = outDirectory
        self.captureScene = captureScene
        self.settings = settings
        self.quitWhenDone = quitWhenDone
        self.loadPasses = loadPasses
        self.screenshots = screenshots
        self.fullScreen = fullScreen
    }

    /// The scenes in tour order. An unknown id is an error, not a silent skip.
    public func scenes() throws(BenchmarkRequestError) -> [BenchmarkScene] {
        if let captureScene, BenchmarkTour.scene(id: captureScene) == nil {
            throw .unknownScene(captureScene)
        }
        guard let sceneIDs else { return preset.scenes() }
        var scenes: [BenchmarkScene] = []
        for id in sceneIDs {
            guard let scene = BenchmarkTour.scene(id: id) else { throw .unknownScene(id) }
            scenes.append(scene)
        }
        return scenes
    }

    /// The overrides as setting ids, checked against `catalog`.
    public func settingOverrides(
        catalog: PlayerSettingsCatalog = .vanilla
    ) throws(BenchmarkRequestError) -> [PlayerSettingID: Double] {
        var overrides: [PlayerSettingID: Double] = [:]
        for (key, value) in settings {
            let id = PlayerSettingID(key)
            guard let definition = catalog.definition(id) else { throw .unknownSetting(key) }
            guard let clamped = definition.clamp(value) else {
                throw .badSettingValue(id: key, value: "\(value)")
            }
            overrides[id] = clamped
        }
        return overrides
    }

    // MARK: - Text forms

    /// `id=value`, where the value is a number, `on` or `off`, or a choice's option text.
    public static func parseSetting(
        _ text: String, catalog: PlayerSettingsCatalog = .vanilla
    ) throws(BenchmarkRequestError) -> (id: String, value: Double) {
        let parts = text.split(separator: "=", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { throw .malformed("expected id=value, got '\(text)'") }
        let (key, word) = (parts[0], parts[1])
        guard let definition = catalog.definition(PlayerSettingID(key)) else {
            throw .unknownSetting(key)
        }
        switch word.lowercased() {
        case "on", "true", "yes": return (key, 1)
        case "off", "false", "no": return (key, 0)
        default: break
        }
        if let number = Double(word) {
            return (key, number)
        }
        if
            case let .choice(options) = definition.kind,
            let index = options.firstIndex(where: { $0.lowercased() == word.lowercased() })
        {
            return (key, Double(index))
        }
        throw .badSettingValue(id: key, value: word)
    }

    public static let appArgument = "--benchmark"
    public static let appRequestArgument = "--benchmark-request"

    /// `--benchmark <preset>` or `--benchmark-request <json>` in the app's arguments.
    public static func fromAppArguments(
        _ arguments: [String]
    ) throws(BenchmarkRequestError) -> Self? {
        if let index = arguments.firstIndex(of: appRequestArgument) {
            guard index + 1 < arguments.count else { throw .malformed("no JSON after the flag") }
            do {
                return try JSONDecoder().decode(Self.self, from: Data(arguments[index + 1].utf8))
            } catch {
                throw .malformed(String(describing: error))
            }
        }
        guard let index = arguments.firstIndex(of: appArgument) else { return nil }
        let word = index + 1 < arguments.count ? arguments[index + 1] : nil
        guard let word, !word.hasPrefix("-") else {
            return Self(quitWhenDone: true)
        }
        guard let preset = BenchmarkPreset(rawValue: word.lowercased()) else {
            throw .malformed("unknown preset '\(word)'; use quick, standard, or full")
        }
        return Self(preset: preset, quitWhenDone: true)
    }

    public var encodedJSON: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = (try? encoder.encode(self)) ?? Data()
        return String(bytes: data, encoding: .utf8) ?? "{}"
    }
}
