// The run order of every per-frame step. A frame runs `FrameStep` after the
// camera moves, then `AssetDrain`, then `WorldTickStep` after the clock.

import Foundation

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

/// Off-main loader results, drained before the world tick, paused or not.
public enum AssetDrain: Int, FramePhase {
    case animationClips
    case menuMovies
    case scripts
    case audio
    case playerBody
    case vehicleWheels
    case cinematicTracks
}

/// The world simulation, after the game clock advances. The delta is zero
/// on a paused frame.
public enum WorldTickStep: Int, FramePhase {
    /// Before scripts, so the Survival Mode plugin sees the answer before it asks.
    case survivalMode
    case scripts
    /// Magic effects write through actor values, so these come first.
    case actorValues
    case magicEffects
    case archery
    case ragdoll
    /// Reads what melee, archery, and the ragdolls did this frame.
    case combatLoop
    /// Package conditions read quest, actor, and reference state.
    case packages
    case perception
    case idles
    case vehicles
    case objectAnimation
    /// Samples the speaker's head bone in the same tick.
    case dialogueCamera
    /// Scenes speak through the dialogue index.
    case story
}
