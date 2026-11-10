// App side of `RagdollCoordinator`: steps it from the renderer's frame hooks and
// answers `RagdollSessionWorld` from the streamer, the render scene, and the
// other session systems. The rules live in the coordinator
// (docs/engine/coordinators.md).

import OpenSkyActorPresentation
import OpenSkyActorsInterface
import OpenSkyCells
public import OpenSkyCombat
public import OpenSkyCombatInterface
import OpenSkyCrimeInterface
import OpenSkyEffects
import OpenSkyFormatsCore
import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyMenusInterface
import OpenSkyPhysics
import OpenSkyPlayer
public import OpenSkyRendering
import OpenSkyScriptingInterface
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
    var streamer: any CellStreamerPort { get }
    var combatRecords: (any CombatRecordsPort)? { get }
}

/// Answers `RagdollSessionWorld` from the session systems `game` owns.
public final class RagdollWorldAdapter {
    public let game: any RagdollWorldHost

    public let recoveryHost: any RagdollRecoveryHost
    public let remainsHost: any RagdollRemainsHost
    public let playerFallHost: any RagdollPlayerFallHost
    public let poseReadsHost: any RagdollPoseReadsHost
    public let deathsHost: any RagdollDeathsHost

    public var recovery: RagdollRecoveryAdapter {
        RagdollRecoveryAdapter(game: recoveryHost, poseReads: poseReads)
    }

    public var remains: RagdollRemainsAdapter {
        RagdollRemainsAdapter(game: remainsHost, poseReads: poseReads)
    }

    public var playerFall: RagdollPlayerFallAdapter {
        RagdollPlayerFallAdapter(game: playerFallHost, recovery: recovery)
    }

    public var poseReads: RagdollPoseReadsAdapter {
        RagdollPoseReadsAdapter(game: poseReadsHost)
    }

    public var deaths: RagdollDeathsAdapter {
        RagdollDeathsAdapter(game: deathsHost, poseReads: poseReads)
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
        game.combatRecords.map { provider in
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
                game.gameSession?.playerAnimation?.setRagdollBones(bones)
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
