// The run order of every per-frame step. A frame runs `FrameStep` after the
// camera moves, then `AssetDrain`, then `WorldTickStep` after the clock.

import Foundation
public import OpenSkyGameData
import OpenSkyWorldInterface

/// Off-main loader results, drained before the world tick, paused or not.
public enum AssetDrain: Int, FramePhase {
    case animationClips
    case menuMovies
    case scripts
    case audio
    case playerBody
    case vehicleWheels
    case modelNodes
    case cinematicTracks
    case loadingCameraPaths
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
    /// After the magic effects, so a water breathing effect that started this frame counts.
    case breath
    case archery
    case ragdoll
    /// Reads what melee, archery, and the ragdolls did this frame.
    case combatLoop
    /// Package conditions read quest, actor, and reference state.
    case packages
    /// After the packages, so a commanded follower's walk reads this frame's moves.
    case followerCommands
    case perception
    case idles
    /// Before the actor graphs, so a flight's events and inputs reach them in the same frame.
    case dragonFlight
    /// After the idles, so an idle's event reaches the actor's graph in the same frame.
    case actorGraphs
    case vehicles
    /// After the vehicles, which clear the seat of a player who rides none.
    case furniture
    case objectAnimation
    /// After the actor and object graphs, so their events reach effect graphs in the same frame.
    case effectGraphs
    /// Samples the speaker's head bone in the same tick.
    case dialogueCamera
    /// Scenes speak through the dialogue index.
    case story
}
