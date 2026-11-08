import Foundation
import OpenSkyFormatsESM
import OpenSkyWorldState

/// One playing scene with its phase and actions.
nonisolated public struct ScenePlayingRow: Equatable, Sendable {
    public let editorID: String
    /// 1-based, as the Creation Kit numbers phases.
    public let phase: Int
    public let phaseCount: Int
    public let phaseName: String?
    public let runningActions: [UInt32]

    public init(
        editorID: String, phase: Int, phaseCount: Int,
        phaseName: String? = nil, runningActions: [UInt32]
    ) {
        self.editorID = editorID
        self.phase = phase
        self.phaseCount = phaseCount
        self.phaseName = phaseName
        self.runningActions = runningActions
    }
}

nonisolated public struct SceneControlSnapshot: Equatable, Sendable {
    public static let rowLimit = 12

    public let playing: [ScenePlayingRow]
    /// Newest last, at most `rowLimit`.
    public let trace: [String]
    public let lines: [String]

    public init(
        playing: [ScenePlayingRow],
        trace: [String],
        lines: [String]
    ) {
        self.playing = playing
        self.trace = trace
        self.lines = lines
    }
}
