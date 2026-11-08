import OpenSkyConditions
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics
import OpenSkyWorldState
import simd

/// Whether an actor is free to run the package its schedule picked.
nonisolated public enum PackageActorActivity: Equatable, Sendable {
    case free
    case fighting
    case dead
    /// A script's `EnableAI(false)`: the actor runs no package and stands still.
    case aiDisabled
}
