// The player's followers during a jail stay: they wait at the jail door and follow
// again afterwards. See docs/engine/jail.md#followers.

import OpenSkyActorsInterface
public import OpenSkyFormatsESM
import OpenSkyScriptingInterface
import OpenSkySessionInterface
import OpenSkyWorldState
import simd

extension CrimeActorsAdapter {
    public func isInCombat(_ key: ReferenceKey) -> Bool {
        game.actorWorld.isInCombat(key)
    }

    /// Living teammates whose package still runs, so they are with the player.
    public func playerFollowers() -> [ReferenceKey] {
        let store = game.worldState
        return store.sortedDirtyKeys().filter { key in
            key != .player
                && store.component(ScriptedReferenceState.self, for: key)?
                .flag(ScriptedStateName.playerTeammate) == true
                && store.component(ActorDeathState.self, for: key)?.isDead != true
                && !game.packages.isSuspended(key)
        }
    }

    /// Stands `follower` at the door `marker` and holds its package there.
    public func parkFollower(_ follower: ReferenceKey, at marker: ReferenceKey) -> Bool {
        guard
            let bridge = game.scripts.bridge,
            let door = bridge.placement(of: marker),
            let moved = bridge.placement(of: follower)
        else { return false }
        _ = game.streamer.stopActor(follower)
        game.packages.suspend(follower)
        bridge.write(
            ReferenceTransformOverride(
                position: door.state.transform.position, scale: moved.state.transform.scale
            ).erased,
            for: follower
        )
        if
            let destination = door.location,
            destination != moved.location || door.worldspace != moved.worldspace
        {
            bridge.relocate(follower, to: destination, worldspace: door.worldspace)
        }
        return true
    }

    public func releaseFollower(_ follower: ReferenceKey) {
        game.packages.resume(follower)
    }

    /// Nil when the two stand in different cells or worldspaces.
    public func distance(of key: ReferenceKey, toMarker marker: ReferenceKey) -> Float? {
        guard
            let bridge = game.scripts.bridge,
            let from = bridge.placement(of: key),
            let to = bridge.placement(of: marker),
            from.worldspace == to.worldspace,
            from.worldspace != nil || from.location == to.location
        else { return nil }
        return simd_distance(from.state.transform.position, to.state.transform.position)
    }
}
