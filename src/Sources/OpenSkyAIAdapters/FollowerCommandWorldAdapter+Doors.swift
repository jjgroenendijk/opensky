// Followers come along when the player changes zone through a load door: "change zones
// (loading screen)" brings them to the player (<https://en.uesp.net/wiki/Skyrim:Followers>).
// See docs/engine/follower-commands.md#load-doors.

import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPlayer
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState

extension FollowerCommandWorldAdapter {
    public var doors: Doors {
        Doors(game: game)
    }

    public struct Doors {
        let game: any FollowerCommandWorldHost

        /// Puts each living teammate beside the player in the cell the door led to. A
        /// follower the player told to wait stays where it waits.
        public func bringFollowers(into scene: any CellScenePort) {
            guard
                let bridge = game.scripts.bridge,
                let destination = scene.location,
                let feet = game.streamer.lastDoorArrival
                ?? game.gameSession?.walkController.feetPosition
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
                key != waiting && !game.packages.isSuspended(key)
                    && game.aiWorld.packageActorActivity(key) != .dead
                    && store.component(ScriptedReferenceState.self, for: key)?
                    .flag(ScriptedStateName.playerTeammate) == true
            }
            for (index, follower) in followers.enumerated() {
                let offset = SIMD3<Float>(Self.followerSpacing * Float(index + 1), 0, 0)
                let scale = bridge.placement(of: follower)?.state.transform.scale ?? 1
                let placed = ReferenceTransformOverride(position: feet + offset, scale: scale)
                // The walk runtime keeps where the follower last stood, and a cell draws an
                // actor there first, so the move must replace that pose too.
                game.streamer.stopActor(follower)
                game.streamer.restActor(follower, at: placed)
                store.set(placed, for: follower, in: destination)
                bridge.relocate(follower, to: destination)
            }
            // An exterior the player returns to is still loaded, so it only draws the
            // followers once it is built again. An interior rebuilds on its own.
            if !followers.isEmpty {
                game.streamer.requestRebuild(of: destination)
            }
        }

        /// Units between the player and each follower placed after a door; not measured.
        static let followerSpacing: Float = 64
    }
}
