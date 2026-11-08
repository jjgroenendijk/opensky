import Foundation
import OpenSkyFormatsCore
import OpenSkyGameData

nonisolated public enum BenchmarkRequestError: Error, Equatable {
    case unknownScene(String)
    case unknownSetting(String)
    case badSettingValue(id: String, value: String)
    case malformed(String)
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

    // MARK: - Text forms

    public static let appArgument = "--benchmark"
    public static let appRequestArgument = "--benchmark-request"
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
