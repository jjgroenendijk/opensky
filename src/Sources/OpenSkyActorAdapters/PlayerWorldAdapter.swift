// App side of `PlayerCoordinator` and `FaceMorphCoordinator`: answers their
// ports from the live renderer, the inventory, and the dialogue menu. The rules
// live in the coordinators (docs/engine/coordinators.md).

public import OpenSkyActorPresentation
import OpenSkyActors
import OpenSkyActorsInterface
import OpenSkyCells
import OpenSkyCombatInterface
public import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyPhysics
public import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkyRendering
public import OpenSkySessionInterface
import OpenSkyWorld
public import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// What `PlayerWorldAdapter` reads from the session. `GameViewController` conforms.
@MainActor
public protocol PlayerWorldHost: AnyObject, SendableMetatype {
    var actorWorld: any ActorWorldPort { get }
    var combat: any CombatPort { get }
    var headTracking: any HeadTrackingPort { get }
    var inventory: any InventoryPort { get }
    var magicWorld: any MagicWorldPort { get }
    var magic: any MagicPort { get }
    var player: any PlayerPort { get }
    var gameSession: (any GameSessionPort)? { get }
    var worldState: any WorldStateStorePort { get }
    var actorRecords: (any ActorRecordsPort)? { get }
    var cellRunner: (any SerialCellBuildRunnerPort)? { get }
}

/// Answers `PlayerWorld` and `FaceMorphWorld` from the session systems `game` owns.
/// Every host a `PlayerWorldAdapter` part reads, all one object.
public typealias PlayerWorldHosts = PlayerFaceHost & PlayerFirstPersonHost & PlayerWorldHost

public final class PlayerWorldAdapter {
    public let game: any PlayerWorldHost
    public let state = PlayerPartState()

    let hosts: any PlayerWorldHosts

    public var firstPerson: PlayerFirstPersonAdapter {
        PlayerFirstPersonAdapter(
            game: hosts,
            state: state
        )
    }

    public var face: PlayerFaceAdapter {
        PlayerFaceAdapter(game: hosts, state: state)
    }

    public init(game: some PlayerWorldHosts) {
        hosts = game
        self.game = game
    }

    /// The rigs assemble on the session's build queue, beside the cells.
    public func rigSource() -> PlayerRigQueue? {
        game.cellRunner.map {
            PlayerRigQueue(runner: $0, fileSystem: game.actorRecords?.scriptFileSystem)
        }
    }
}

/// The player's rigs assemble on the session's build queue, beside the cells.
public final class PlayerRigQueue: PlayerRigSource {
    public let playerAssetFileSystem: (any GameFileSource)?
    private let runner: any SerialCellBuildRunnerPort

    public init(runner: any SerialCellBuildRunnerPort, fileSystem: (any GameFileSource)?) {
        self.runner = runner
        playerAssetFileSystem = fileSystem
    }

    public func requestPlayerRig(_ request: PlayerRigRequest) {
        runner.enqueuePlayerRig(request)
    }

    public func drainPlayerRigs() -> [PlayerRenderRigResult] {
        runner.drainCompletedPlayerRigs()
    }
}

extension PlayerWorldAdapter: PlayerWorld {
    public var playerLocomotion: LocomotionBridge? {
        state.locomotion()
    }

    public var isPlayerGrounded: Bool {
        game.gameSession?.walkController.isGrounded ?? true
    }

    public var playerEquippedSet: [FormID]? {
        guard
            let equipment = game.inventory.equipment,
            equipment.inventory.hasRuntimeInventory(InventoryHolder.player)
        else { return nil }
        return equipment.equipped(on: InventoryHolder.player)
    }

    public var playerWeaponsDrawn: Bool {
        game.combat.isWeaponDrawn
    }

    public var playerAppearanceOverride: PlayerAppearanceOverride? {
        PlayerIdentityReads(game: game).playerAppearanceOverride
    }

    public var playerBehaviorProject: String? {
        PlayerIdentityReads(game: game).playerBehaviorProject
    }
}

extension PlayerWorldAdapter: FaceMorphWorld {}

extension PlayerWorldAdapter: HeadTrackingWorld {}

/// The player's chosen look and behaviour graph, for `PlayerWorldAdapter`.
struct PlayerIdentityReads {
    let game: any PlayerWorldHost

    var playerAppearanceOverride: PlayerAppearanceOverride? {
        game.worldState.component(PlayerIdentityState.self, for: .player).map { identity in
            var appearance = PlayerAppearanceOverride(
                race: identity.race, isFemale: identity.isFemale,
                headParts: identity.face.headParts, hairColor: identity.face.hairColor
            )
            appearance.faceMorphs = identity.face.morphs
            appearance.faceParts = identity.face.parts
            appearance.weight = identity.face.weight
            appearance.faceTexture = identity.face.faceTexture
            appearance.tints = identity.face.tints.map {
                PlayerAppearanceTint(
                    maskIndex: $0.maskIndex,
                    color: $0.color,
                    strength: $0.strength
                )
            }
            return appearance
        }
    }

    /// The race's graph for the player's sex: `defaultfemale.hkx` for a female human, or a
    /// beast race's own project.
    var playerBehaviorProject: String? {
        guard
            let identity = game.worldState.component(PlayerIdentityState.self, for: .player),
            let race = game.actorRecords?.actorValueBaselines?.resolver?
                .races[identity.race.rawValue]
        else { return nil }
        let graphs = race.details.behaviorGraphs
        guard let model = (identity.isFemale ? graphs.female : nil) ?? graphs.male else {
            return nil
        }
        return ActorGraphCore.projectPath(modelPath: model.path)
    }
}
