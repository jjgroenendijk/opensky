// Followers come along when the player changes zone through a load door: "change zones
// (loading screen)" brings them to the player (<https://en.uesp.net/wiki/Skyrim:Followers>).
// See docs/engine/follower-commands.md#load-doors.

import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPlayer
import OpenSkyScripting
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState

extension FollowerCommandWorldAdapter {
    /// Puts each living teammate beside the player in the cell the door led to. A
    /// follower the player told to wait stays where it waits.
    public func bringFollowers(into scene: any CellScenePort) {
        guard
            let bridge = game.scripts.bridge,
            let destination = scene.location,
            let feet = game.gameSession?.walkController.feetPosition
        else { return }
        let waiting: ReferenceKey? = if
            case let .waiting(follower, _) = game.followerCommands
                .phase
        {
            follower
        } else {
            nil
        }
        let store = game.worldState
        let followers = store.sortedDirtyKeys().filter { key in
            key != waiting && game.aiWorld.packageActorActivity(key) != .dead
                && store.component(ScriptedReferenceState.self, for: key)?
                .flag(ScriptedStateName.playerTeammate) == true
        }
        for (index, follower) in followers.enumerated() {
            let offset = SIMD3<Float>(Self.followerSpacing * Float(index + 1), 0, 0)
            let scale = bridge.placement(of: follower)?.state.transform.scale ?? 1
            bridge.write(
                ReferenceTransformOverride(position: feet + offset, scale: scale).erased,
                for: follower
            )
            bridge.relocate(follower, to: destination)
        }
    }

    /// Units between the player and each follower placed after a door; not measured.
    private static let followerSpacing: Float = 64
}
