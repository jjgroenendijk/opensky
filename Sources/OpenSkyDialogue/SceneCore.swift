// The readout text of scene playback. Values in, values out.

import Foundation
import OpenSkyDialogueInterface
import OpenSkyFormatsESM

public enum SceneCore {
    /// Characters read per second, and the shortest a response lasts. OpenSky's
    /// estimate, for a response with no voice file.
    static let charactersPerSecond: Float = 15
    static let shortestResponse: Float = 1.5

    /// Seconds the responses take, one text each; nil text counts as the default line.
    public static func lineDuration(texts: [String?]) -> Float {
        guard !texts.isEmpty else { return SceneRuntime.defaultLineDuration }
        return texts.reduce(0) { total, text in
            guard let text else { return total + SceneRuntime.defaultLineDuration }
            return total + max(shortestResponse, Float(text.count) / charactersPerSecond)
        }
    }

    public static func listRow(_ entry: CatalogScene, isPlaying: Bool) -> SceneListRow {
        let aliases = Set(entry.scene.actions.compactMap(\.aliasID))
        return SceneListRow(
            editorID: entry.editorID,
            phaseCount: entry.scene.phases.count,
            actionCount: entry.scene.actions.count,
            actorCount: aliases.count,
            isPlaying: isPlaying
        )
    }

    public static func playingRow(
        _ entry: CatalogScene,
        state: SceneRuntimeState
    ) -> ScenePlayingRow {
        ScenePlayingRow(
            editorID: entry.editorID,
            phase: Int(state.phase) + 1,
            phaseCount: entry.scene.phases.count,
            runningActions: state.running.map(\.action)
        )
    }

    public static func text(_ event: SceneEvent, catalog: SceneCatalog) -> String {
        let name = catalog.scene(event.scene)?.editorID ?? event.scene.description
        return "\(name): \(text(step: event.step))"
    }

    /// Phases read 1-based, as the Creation Kit numbers them.
    public static func text(step: SceneStep) -> String {
        switch step {
        case .began: "began"
        case let .phaseSkipped(phase): "phase \(phase + 1) skipped"
        case let .phaseStarted(phase): "phase \(phase + 1) started"
        case let .phaseCompleted(phase, byConditions):
            "phase \(phase + 1) done by \(byConditions ? "conditions" : "actions")"
        case let .fragment(name): "fragment \(name)"
        case let .fragmentUnrun(name): "fragment \(name) not run"
        case .repeated: "repeated"
        case let .ended(reason): "ended (\(text(reason: reason)))"
        default: actionText(step)
        }
    }

    private static func actionText(_ step: SceneStep) -> String {
        switch step {
        case let .actionStarted(action): "action \(action) started"
        case let .actionCompleted(action): "action \(action) done"
        case let .line(line): text(line: line)
        case let .voiceLoading(action): "action \(action): voice file loading"
        case let .packageStarted(action, actor): "action \(action): \(actor) runs its package"
        case let .packageDone(action): "action \(action): package done"
        case let .noLine(action): "action \(action): no line passed"
        case let .emptyAlias(action): "action \(action): actor alias empty"
        case let .unsupportedAction(action, type): "action \(action): type \(type) not run"
        default: ""
        }
    }

    public static func text(line: SceneLine) -> String {
        "\(line.speaker) says \(line.info) in topic \(line.topic) for "
            + String(format: "%.1f s", line.seconds)
    }

    static func text(reason: SceneEndReason) -> String {
        switch reason {
        case .finished: "finished"
        case .stopped: "stopped"
        case .questStopped: "quest stopped"
        }
    }
}
