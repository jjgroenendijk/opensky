// App side of `PlayerCoordinator` and `FaceMorphCoordinator`: answers their
// ports from the live renderer, the inventory, and the dialogue menu. The rules
// live in the coordinators (docs/engine/coordinators.md).

import OpenSkyActorPresentation
import OpenSkyActorsInterface
import OpenSkyCells
import OpenSkyCombat
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyMagic
import OpenSkyMagicInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyWorld
import OpenSkyWorldState
import simd

/// What `PlayerWorldAdapter` reads from the session. `GameViewController` conforms.
@MainActor
protocol PlayerWorldHost: AnyObject {
    var actorWorld: ActorWorldAdapter { get }
    var audio: AudioCoordinator { get }
    var combat: CombatCoordinator { get }
    var dialogueMenu: DialogueMenuController { get }
    var headTracking: HeadTrackingCoordinator { get }
    var inventory: InventoryCoordinator { get }
    var magicWorld: MagicWorldAdapter { get }
    var magic: MagicCoordinator { get }
    var player: PlayerCoordinator { get }
    var renderer: Renderer? { get }
    var gameSession: GameSession? { get }
    var streamer: CellStreamer? { get }
    var worldState: WorldStateStore { get }
    var worldData: WorldDataStores? { get }
    var cellRunner: SerialCellBuildRunner? { get }
    var cameraInput: CameraInputState { get }
}

/// Answers `PlayerWorld` and `FaceMorphWorld` from the session systems `game` owns.
final class PlayerWorldAdapter {
    unowned let game: any PlayerWorldHost

    init(game: any PlayerWorldHost) {
        self.game = game
    }

    /// The rigs assemble on the session's build queue, beside the cells.
    func makePlayer() -> PlayerCoordinator {
        let source = game.cellRunner.map {
            PlayerRigQueue(runner: $0, fileSystem: game.worldData?.scriptFileSystem)
        }
        return PlayerCoordinator(input: game.cameraInput, world: self, source: source)
    }

    /// The graph and the body outlive every cell, so this is not streaming.
    func wirePlayerBody(gameSession: GameSession) {
        let player = game.player
        player.requestBody()
        gameSession.assetDrains.register(.playerBody) { [weak player] _ in
            player?.drainClipLoads()
        }
        gameSession.frameSteps.register(.playerBody) { [weak player] _ in
            player?.refreshBody()
        }
    }

    /// Copies what combat, magic, and the head tracking setting report into the
    /// actor-state graph inputs.
    func wireActorState(gameSession: GameSession) {
        gameSession.frameSteps.register(.actorState) { [weak game, weak gameSession] _ in
            guard let game, let locomotion = gameSession?.locomotion else { return }
            var inputs = locomotion.actorState
            if let melee = game.combat.melee {
                inputs.weaponDrawn = melee.state.drawState.isWeaponInHand
                inputs.isAttacking = melee.state.attackPhase.isAttacking
                inputs.isPowerAttacking = melee.strikeKind.isPowerAttack
                inputs.isBlocking = melee.state.isBlocking
                inputs.rightHandType = melee.weapon.handType.rawValue
                inputs.leftHandType = melee.offHand.rawValue
            }
            if let holder = game.actorWorld.actorValueHolder(for: .player) {
                inputs.isBeastRace = game.magicWorld.actorHasKeyword(
                    ActorStateGraphNames.isBeastRace, on: holder
                )
            }
            inputs.isBowDrawn = game.combat.archery?.state.phase.isFullyDrawn ?? false
            inputs.castingLeft = game.magic.wantsCast(.left)
            inputs.castingRight = game.magic.wantsCast(.right)
            inputs.wantsVoice = game.magic.shoutMachine.wantsVoice
            inputs.headTracking = game.headTracking.isEnabled
            locomotion.actorState = inputs
        }
    }
}

/// The player's rigs assemble on the session's build queue, beside the cells.
final class PlayerRigQueue: PlayerRigSource {
    let playerAssetFileSystem: (any GameFileSource)?
    private let runner: SerialCellBuildRunner

    init(runner: SerialCellBuildRunner, fileSystem: (any GameFileSource)?) {
        self.runner = runner
        playerAssetFileSystem = fileSystem
    }

    func requestPlayerRig(_ request: PlayerRigRequest) {
        runner.enqueuePlayerRig(request)
    }

    func drainPlayerRigs() -> [PlayerRigLoadResult] {
        runner.drainCompletedPlayerRigs()
    }
}

extension PlayerWorldAdapter: PlayerWorld {
    var playerLocomotion: LocomotionBridge? {
        game.gameSession?.locomotion
    }

    var playerBreath: PlayerBreath? {
        game.gameSession?.breath
    }

    var isWalkModeActive: Bool {
        game.gameSession?.movementMode.isPlayerControlled ?? false
    }

    var isPlayerGrounded: Bool {
        game.gameSession?.walkController.isGrounded ?? true
    }

    var playerEquippedSet: [FormID]? {
        guard
            let equipment = game.inventory.equipment,
            equipment.inventory.hasRuntimeInventory(InventoryHolder.player)
        else { return nil }
        return equipment.equipped(on: InventoryHolder.player)
    }

    var playerWeaponsDrawn: Bool {
        game.combat.isWeaponDrawn
    }

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

    /// The footstep set follows the boots of the assembly just built.
    func showPlayerBody(_ body: PlayerBody) throws {
        game.audio.updateFootstepSet(feetArmatures: body.feetArmatures)
        try game.gameSession?.setPlayerBody(body)
    }

    func showFirstPersonRig(_ rig: PlayerFirstPersonRig) throws {
        try game.gameSession?.setPlayerFirstPersonRig(rig)
    }

    var playerFirstPersonRig: PlayerFirstPersonRig? {
        game.gameSession?.playerFirstPersonRig
    }

    var areFirstPersonArmsVisible: Bool {
        game.renderer?.areFirstPersonArmsVisible ?? false
    }

    var firstPersonFOVYRadians: Float? {
        game.gameSession?.firstPersonCamera.fovYRadians
    }

    func setFirstPersonFOVY(radians: Float) {
        game.gameSession?.setFirstPersonFOVY(radians: radians)
    }

    var firstPersonArmsEnabled: Bool? {
        game.gameSession?.firstPersonArmsEnabled
    }

    func setFirstPersonArmsEnabled(_ enabled: Bool) {
        game.gameSession?.firstPersonArmsEnabled = enabled
    }
}

extension PlayerWorldAdapter: FaceMorphWorld {
    var faceMorphSubject: FormID? {
        guard let key = game.dialogueMenu.speakerOrTarget else { return nil }
        return game.streamer?.referenceEntry(key: key)?.placedActor?.formID
    }

    func faceMorphPlayback(for actor: FormID) -> FaceMorphPlayback? {
        game.renderer?.scene.faceMorphPlayback(for: actor)
    }

    var faceMorphPlaybacks: [FaceMorphPlayback] {
        game.renderer?.scene.animations.compactMap { $0 as? FaceMorphPlayback } ?? []
    }
}

extension PlayerWorldAdapter: HeadTrackingWorld {
    var headTrackingSubjects: [HeadTrackingSubject] {
        guard
            let renderer = game.renderer, let gameSession = game.gameSession,
            let streamer = game.streamer else { return [] }
        let deltas = gameSession.instancePoses.npcDeltas
        return game.actorWorld.combatActors().compactMap { actor in
            guard
                !actor.isDead,
                let formID = streamer.referenceEntry(key: actor.key)?.placedActor?.formID,
                let playback = renderer.scene.actorPlayback(for: formID)
            else { return nil }
            let delta = deltas[formID.rawValue] ?? matrix_identity_float4x4
            return HeadTrackingSubject(
                key: actor.key, playback: playback, worldFromActor: delta * playback.transform
            )
        }
    }

    func headPosition(of key: ReferenceKey) -> SIMD3<Float>? {
        if key == .player {
            return game.gameSession.map {
                $0.walkController.feetPosition + SIMD3(0, 0, PlayerCapsule.standard.eyeHeight)
            }
        }
        guard let actor = game.actorWorld.combatActor(key: key) else {
            return nil
        }
        return actor.feet + SIMD3(0, 0, actor.capsule.eyeHeight * max(actor.scale, 0))
    }
}
