// What one benchmark run asks for. The launcher, the app's `--benchmark` flag,
// and the agent control command all build this one value. A run starts hidden
// and muted unless it asks otherwise, so it does not take over the machine.

import Foundation
public import OpenSkyGameData

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

/// Where the tour draws. `hidden` keeps the window off the screen, yet the
/// view's own frame loop runs at the same rate as on the screen.
nonisolated public enum BenchmarkDisplay: String, Codable, CaseIterable, Sendable {
    case hidden
    case windowed
    case fullScreen

    public var title: String {
        switch self {
        case .hidden: "Hidden"
        case .windowed: "Window"
        case .fullScreen: "Full screen"
        }
    }
}

/// The drawable size in pixels, so a hidden run and a run on the screen compare.
nonisolated public struct BenchmarkFrameSize: Codable, Equatable, Sendable {
    public var width: Int
    public var height: Int

    public static let hiddenDefault = Self(width: 1920, height: 1080)

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    /// `1920x1080`; both sides between 64 and 16384.
    public static func parse(_ text: String) throws(BenchmarkRequestError) -> Self {
        let parts = text.lowercased().split(separator: "x").compactMap { Int($0) }
        guard parts.count == 2, parts.allSatisfy({ (64 ... 16384).contains($0) }) else {
            throw .malformed("size must be WIDTHxHEIGHT in pixels, got '\(text)'")
        }
        return Self(width: parts[0], height: parts[1])
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
    public var display: BenchmarkDisplay
    /// The drawable size of a hidden or windowed run; nil keeps the window's size.
    public var frameSize: BenchmarkFrameSize?
    /// Silences the output only; the audio update still runs and is measured.
    public var muted: Bool

    public init(
        preset: BenchmarkPreset = .standard, sceneIDs: [String]? = nil, overlay: Bool = true,
        outDirectory: String? = nil, captureScene: String? = nil,
        settings: [String: Double] = [:], quitWhenDone: Bool = false, loadPasses: Bool = true,
        screenshots: Bool = false, display: BenchmarkDisplay = .hidden,
        frameSize: BenchmarkFrameSize? = nil, muted: Bool = true
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
        self.display = display
        self.frameSize = frameSize
        self.muted = muted
    }

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
