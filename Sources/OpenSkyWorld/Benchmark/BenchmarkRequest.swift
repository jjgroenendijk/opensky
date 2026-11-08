// What one benchmark run asks for. The launcher, the app's `--benchmark` flag,
// and the agent control command all build this one value. A run starts hidden
// and muted unless it asks otherwise, so it does not take over the machine.

import Foundation
import OpenSkyFormatsCore
public import OpenSkyGameData
public import OpenSkyWorldInterface

nonisolated extension BenchmarkRequestError {
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

nonisolated extension BenchmarkRequestError: CustomStringConvertible {}

nonisolated extension BenchmarkRequest {
    /// The size the window takes for the run; nil leaves it as it is.
    public var effectiveFrameSize: BenchmarkFrameSize? {
        switch display {
        case .hidden: frameSize ?? .hiddenDefault
        case .windowed: frameSize
        case .fullScreen: nil
        }
    }

    /// The scenes in tour order. An unknown id is an error, not a silent skip.
    public func scenes() throws(BenchmarkRequestError) -> [BenchmarkScene] {
        if display == .fullScreen, frameSize != nil {
            throw .malformed("a full-screen run takes the display's size; drop the frame size")
        }
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
}

nonisolated extension BenchmarkRequest {
    public var encodedJSON: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = attempt { try encoder.encode(self) } ?? Data()
        return String(bytes: data, encoding: .utf8) ?? "{}"
    }
}
