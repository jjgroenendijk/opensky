// What scene playback did, one entry per step, like the dialogue selection
// trace. The sidebar shows it; tests assert on it. See docs/engine/scenes.md.

import Foundation
import OpenSkyFormatsESM

nonisolated public enum SceneEndReason: Equatable, Sendable {
    /// The last phase ended.
    case finished
    case stopped
    case questStopped
}

/// A line a dialogue action selected and marked said.
nonisolated public struct SceneLine: Equatable, Sendable {
    public let speaker: ReferenceKey
    public let topic: FormID
    public let info: FormID
}

nonisolated public enum SceneStep: Equatable, Sendable {
    case began
    case phaseSkipped(UInt32)
    case phaseStarted(UInt32)
    /// True when the completion conditions ended it, false when its actions did.
    case phaseCompleted(UInt32, byConditions: Bool)
    case actionStarted(UInt32)
    case actionCompleted(UInt32)
    case line(SceneLine)
    /// The dialogue action's topic had no response that passed for the speaker.
    case noLine(UInt32)
    /// The action's alias is empty, so it counts as done at once, as for a dead actor.
    case emptyAlias(UInt32)
    /// An action type OpenSky does not run yet, such as a package. Counted, done at once.
    case unsupportedAction(UInt32, type: UInt16)
    case fragment(String)
    /// A declared fragment nothing ran.
    case fragmentUnrun(String)
    case repeated
    case ended(SceneEndReason)
}

nonisolated public struct SceneEvent: Equatable, Sendable {
    public let scene: FormID
    public let step: SceneStep

    public init(scene: FormID, step: SceneStep) {
        self.scene = scene
        self.step = step
    }
}

nonisolated public enum SceneError: Error, Equatable, Sendable {
    case unknownScene(FormID)
    /// A scene can start only while its quest runs.
    case questNotRunning(FormID)
}
