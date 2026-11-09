public import OpenSkyFormatsESM
import OpenSkyPlayer
public import OpenSkySessionInterface
import OpenSkyWorldState
import simd

/// What `EffectsLocatorAdapter` reads from the session.
@MainActor
public protocol EffectsLocatorHost: AnyObject {
    var gameSession: (any GameSessionPort)? { get }
    var scripts: any ScriptPort { get }
    var streamer: any CellStreamerPort { get }
}

/// Part of `EffectsWorldAdapter` that finds where a reference stands.
public struct EffectsLocatorAdapter {
    public let game: any EffectsLocatorHost
}

extension EffectsLocatorAdapter {
    /// Where a reference stands now: the player's feet, a moved NPC's capsule, or its
    /// placement.
    public func trapPosition(of reference: ReferenceKey) -> SIMD3<Float>? {
        if reference == .player {
            return game.gameSession?.walkController.feetPosition
        }
        return game.streamer.npcTransform(for: reference)?.position
            ?? game.scripts.bridge?.referenceState(for: reference)?.transform.position
    }
}
