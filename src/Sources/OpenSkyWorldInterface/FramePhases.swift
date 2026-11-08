import Foundation
public import OpenSkyGameData

/// Steps that run after the camera advances, with the camera position.
public enum FrameStep: Int, FramePhase {
    case menuRouting
    /// Places the benchmark camera before anything reads the view.
    case benchmark
    /// May call `setScene` before this frame encodes.
    case streaming
    case messages
    case lockpicking
    case playerBody
    case actorValues
    case spellCasting
    case hazards
    case effects
    /// Melee reads graph events before archery and ragdolls take theirs.
    case melee
    /// After melee, so a swing that started this frame reaches the actor-state graph.
    case actorState
    case ragdoll
    case animationEvents
    case cinematicCamera
    case loadingScreen
    case sessionStartTiming
    /// After streaming, so the HUD reads this frame's streamer update.
    case hud
    case newGameTeleport
}

/// The handlers of the audio engine's first start, which runs once.
public enum AudioEngineStartStep: Int, FramePhase {
    /// Stored volumes reach the new engine.
    case playerSettings
}
