// The Scenes section's seam: the catalog search, start and stop, the playing
// scenes, and the last steps and lines. The text lives in `SceneCore`, so it is
// testable without a window. See docs/engine/scenes.md.

import Foundation
import OpenSkyDialogueInterface
import OpenSkyFormatsESM
import OpenSkyWorldState

/// One scene as the list shows it.
nonisolated public struct SceneListRow: Equatable, Sendable {
    public let editorID: String
    public let phaseCount: Int
    public let actionCount: Int
    public let actorCount: Int
    public let isPlaying: Bool
}

/// One playing scene with its phase and actions.
nonisolated public struct ScenePlayingRow: Equatable, Sendable {
    public let editorID: String
    /// 1-based, as the Creation Kit numbers phases.
    public let phase: Int
    public let phaseCount: Int
    public let runningActions: [UInt32]
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

@MainActor
public protocol SceneControlProviding: AnyObject {
    var sceneSnapshot: SceneControlSnapshot { get }
    /// Scenes whose editor ID contains `filter`, at most `SceneControlSnapshot.rowLimit`.
    func sceneRows(matching filter: String) -> [SceneListRow]
    func startScene(editorID: String)
    func stopScene(editorID: String)
}

extension SceneCoordinator: SceneControlProviding {
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

    public func sceneRows(matching filter: String) -> [SceneListRow] {
        let needle = filter.trimmingCharacters(in: .whitespaces).lowercased()
        return catalog.all.lazy
            .filter { needle.isEmpty || $0.editorID.lowercased().contains(needle) }
            .prefix(SceneControlSnapshot.rowLimit)
            .map { SceneCore.listRow($0, isPlaying: self.playing.contains($0.formID)) }
    }

    public func startScene(editorID: String) {
        guard let entry = catalog.scene(editorID: editorID) else {
            lastOutcome = "no scene named \(editorID)"
            return
        }
        start(entry.formID)
    }

    public func stopScene(editorID: String) {
        guard let entry = catalog.scene(editorID: editorID) else {
            lastOutcome = "no scene named \(editorID)"
            return
        }
        stop(entry.formID)
    }
}

/// Lets the app's provider object stand in for its `SceneCoordinator`.
public protocol SceneControlForwarding: SceneControlProviding {
    var scenes: SceneCoordinator { get }
}

extension SceneControlForwarding {
    public var sceneSnapshot: SceneControlSnapshot {
        scenes.sceneSnapshot
    }

    public func sceneRows(matching filter: String) -> [SceneListRow] {
        scenes.sceneRows(matching: filter)
    }

    public func startScene(editorID: String) {
        scenes.startScene(editorID: editorID)
    }

    public func stopScene(editorID: String) {
        scenes.stopScene(editorID: editorID)
    }
}
