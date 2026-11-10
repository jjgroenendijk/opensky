// What scene playback did, one entry per step, like the dialogue selection
// trace. Agent control reads it; tests assert on it. See docs/engine/scenes.md.

import Foundation
public import OpenSkyDialogueInterface
public import OpenSkyFormatsESM

nonisolated public enum SceneEndReason: Equatable, Sendable {
    /// The last phase ended.
    case finished
    case stopped
    case questStopped
    /// `ForceStart()` of a scene with the same actors, or a new scene that needs an
    /// actor of this interruptible one.
    case interrupted
    /// An actor's behaviour flags end the scene, for example on death.
    case actorBehavior
}

nonisolated public enum SceneStep: Equatable, Sendable {
    case began
    case phaseSkipped(UInt32)
    case phaseStarted(UInt32)
    /// True when the completion conditions ended it, false when its actions did.
    case phaseCompleted(UInt32, byConditions: Bool)
    case actionStarted(UInt32)
    case actionCompleted(UInt32)
    /// The line's clock started: its voice file loaded, or it has none.
    case line(SceneLine)
    /// The line waits for its voice file to load before its clock starts.
    case voiceLoading(UInt32)
    /// The dialogue action's topic had no response that passed for the speaker.
    case noLine(UInt32)
    /// The action's alias is empty, so it counts as done at once, as for a dead actor.
    case emptyAlias(UInt32)
    /// The action's actor is dead, or optional and busy in another scene. Done at once.
    case actorUnavailable(UInt32)
    /// An actor this scene needs is in another scene, so the next phase waits.
    case waitingForActors
    /// An actor's behaviour flags paused the scene, for example in combat.
    case paused
    case resumed
    /// The actor runs the action's packages ahead of its schedule.
    case packageStarted(UInt32, actor: ReferenceKey)
    /// The package reached its Done state.
    case packageDone(UInt32)
    /// An action type the Creation Kit does not list. Counted, done at once.
    case unsupportedAction(UInt32, type: UInt16)
    case fragment(String)
    /// A declared fragment nothing ran.
    case fragmentUnrun(String)
    case repeated
    case ended(SceneEndReason)
}

nonisolated public struct SceneEvent: Equatable, Sendable {
    let scene: FormID
    let step: SceneStep
}

nonisolated public enum SceneError: Error, Equatable, Sendable {
    case unknownScene(FormID)
    /// A scene can start only while its quest runs.
    case questNotRunning(FormID)
}
