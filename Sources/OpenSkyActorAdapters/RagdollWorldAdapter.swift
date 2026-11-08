// App side of `RagdollCoordinator`: steps it from the renderer's frame hooks and
// answers `RagdollSessionWorld` from the streamer, the render scene, and the
// other session systems. The rules live in the coordinator
// (docs/engine/coordinators.md).

import OpenSkyActorPresentation
import OpenSkyActors
import OpenSkyActorsInterface
public import OpenSkyCells
public import OpenSkyCombat
public import OpenSkyCombatInterface
import OpenSkyCrime
import OpenSkyEffects
import OpenSkyFormatsCore
import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyMagic
import OpenSkyMenus
import OpenSkyPhysics
import OpenSkyPlayer
public import OpenSkyRendering
import OpenSkyScripting
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// What `RagdollWorldAdapter` reads from the session. `GameViewController` conforms.
@MainActor
public protocol RagdollWorldHost: AnyObject {
    var audioFileSystem: (any GameFileSource)? { get }
    var cinematicWorld: any CinematicCameraWorldPort { get }
    var crime: any CrimePort { get }
    var ragdoll: any RagdollPort { get }
    var renderer: (any RendererPort)? { get }
    var gameSession: (any GameSessionPort)? { get }
    var streamer: (any CellStreamerPort)? { get }
    var worldData: WorldDataStores? { get }
}

/// Answers `RagdollSessionWorld` from the session systems `game` owns.
public final class RagdollWorldAdapter {
    public unowned let game: any RagdollWorldHost

    public let recoveryHost: any RagdollRecoveryHost
    public let remainsHost: any RagdollRemainsHost
    public let playerFallHost: any RagdollPlayerFallHost
    public let poseReadsHost: any RagdollPoseReadsHost
    public let deathsHost: any RagdollDeathsHost

    public var recovery: RagdollRecoveryAdapter {
        RagdollRecoveryAdapter(owner: self, game: recoveryHost)
    }

    public var remains: RagdollRemainsAdapter {
        RagdollRemainsAdapter(owner: self, game: remainsHost)
    }

    public var playerFall: RagdollPlayerFallAdapter {
        RagdollPlayerFallAdapter(
            owner: self,
            game: playerFallHost
        )
    }

    public var poseReads: RagdollPoseReadsAdapter {
        RagdollPoseReadsAdapter(
            owner: self,
            game: poseReadsHost
        )
    }

    public var deaths: RagdollDeathsAdapter {
        RagdollDeathsAdapter(owner: self, game: deathsHost)
    }

    public init(game: some RagdollWorldHost & RagdollRecoveryHost & RagdollRemainsHost &
        RagdollPlayerFallHost & RagdollPoseReadsHost & RagdollDeathsHost)
    {
        recoveryHost = game
        remainsHost = game
        playerFallHost = game
        poseReadsHost = game
        deathsHost = game
        self.game = game
    }

    /// Nil without game data, so the runtime stays nil.
    public func sessionData() -> RagdollSessionData? {
        game.worldData.map { provider in
            RagdollSessionData(
                collisionModels: game.audioFileSystem.map(NIFCollisionLibrary.init),
                deathSettings: DeathSettings.resolve(store: provider.gameSettings)
            )
        }
    }

    public func run(_ commands: [RagdollCommand]) {
        for command in commands {
            switch command {
            case let .reportMurder(key):
                game.crime.reportMurder(of: key)
                game.cinematicWorld.actorDied(key)
            case let .publishPoses(poses):
                game.renderer?.scene.ragdollPoses = poses
            case let .publishPlayerRagdoll(bones):
                game.gameSession?.playerBody?.animation.setRagdollBones(bones)
            case let .publishSeveredHeads(poses):
                game.renderer?.scene.severedHeadPoses = poses
            case let .enterBleedout(key):
                recovery.enterBleedout(key)
            case let .leaveBleedout(key):
                recovery.leaveBleedout(key)
            case let .enterKnockdown(key):
                recovery.enterKnockdown(key)
            case let .getUp(key, feet, yaw):
                recovery.getUp(key, feet: feet, yaw: yaw)
            case let .endKnockdown(key):
                recovery.endKnockdown(key)
            }
        }
    }
}

extension RagdollWorldAdapter: RagdollSessionWorld {}

extension RagdollWorldAdapter: RagdollWorldPort {}
