// The Scenes section's seam: the catalog search, start and stop, the playing
// scenes, and the last steps and lines. The text lives in `SceneCore`, so it is
// testable without a window. See docs/engine/scenes.md.

import Foundation
import OpenSkyDialogueInterface
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

    public let sceneCount: Int
    public let playing: [ScenePlayingRow]
    /// Newest last, at most `rowLimit`.
    public let trace: [String]
    public let lines: [String]
    public let lastOutcome: String?
}

extension SceneCoordinator {
    public var sceneSnapshot: SceneControlSnapshot {
        let limit = SceneControlSnapshot.rowLimit
        let playingRows = catalog.all.compactMap { entry -> ScenePlayingRow? in
            guard let state = dialogue.store.component(SceneRuntimeState.self, for: entry.key)
            else { return nil }
            return SceneCore.playingRow(entry, state: state)
        }
        return SceneControlSnapshot(
            sceneCount: catalog.count,
            playing: Array(playingRows.prefix(limit)),
            trace: trace.suffix(limit).map { SceneCore.text($0, catalog: catalog) },
            lines: lines.suffix(limit).map(SceneCore.text(line:)),
            lastOutcome: lastOutcome
        )
    }
}
