// App side of `PlayerCoordinator` and `FaceMorphCoordinator`: answers their
// ports from the live renderer, the inventory, and the dialogue menu. The rules
// live in the coordinators (docs/engine/coordinators.md).

import OpenSkyActorPresentation
import OpenSkyActors
import OpenSkyActorsInterface
import OpenSkyCells
import OpenSkyCombat
import OpenSkyCombatInterface
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
import OpenSkySession
import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// What `PlayerWorldAdapter` reads from the session. `GameViewController` conforms.
@MainActor
protocol PlayerWorldHost: AnyObject {
    var actorWorld: any ActorWorldPort { get }
    var actorValues: any ActorValuePort { get }
    var audio: any AudioPort { get }
    var combat: any CombatPort { get }
    var dialogueMenu: any DialogueMenuPort { get }
    var headTracking: any HeadTrackingPort { get }
    var inventory: any InventoryPort { get }
    var magicWorld: any MagicWorldPort { get }
    var magic: any MagicPort { get }
    var player: any PlayerPort { get }
    var renderer: (any RendererPort)? { get }
    var gameSession: (any GameSessionPort)? { get }
    var streamer: (any CellStreamerPort)? { get }
    var worldState: any WorldStateStorePort { get }
    var worldData: WorldDataStores? { get }
    var cellRunner: (any SerialCellBuildRunnerPort)? { get }
}

/// Answers `PlayerWorld` and `FaceMorphWorld` from the session systems `game` owns.
final class PlayerWorldAdapter {
    unowned let game: any PlayerWorldHost
    /// The session's player parts. The composition root sets these, so the host stays port-only.
    var locomotion: () -> LocomotionBridge? = { nil }
    var firstPersonRig: () -> PlayerFirstPersonRig? = { nil }
    var playerFace: () -> FaceMorphPlayback? = { nil }

    init(game: any PlayerWorldHost) {
        self.game = game
    }

    /// The rigs assemble on the session's build queue, beside the cells.
    func rigSource() -> PlayerRigQueue? {
        game.cellRunner.map {
            PlayerRigQueue(runner: $0, fileSystem: game.worldData?.scriptFileSystem)
        }
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
            inputs.weight = game.worldState.component(PlayerIdentityState.self, for: .player)?
                .face.weight ?? 50
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
    private let runner: any SerialCellBuildRunnerPort

    init(runner: any SerialCellBuildRunnerPort, fileSystem: (any GameFileSource)?) {
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
        locomotion()
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

    /// The race's graph for the player's sex: `defaultfemale.hkx` for a female human, or a
    /// beast race's own project.
    var playerBehaviorProject: String? {
        guard
            let identity = game.worldState.component(PlayerIdentityState.self, for: .player),
            let race = game.worldData?.actorValueBaselines?.resolver?.races[identity.race.rawValue]
        else { return nil }
        let graphs = race.details.behaviorGraphs
        guard let model = (identity.isFemale ? graphs.female : nil) ?? graphs.male else {
            return nil
        }
        return ActorGraphCore.projectPath(modelPath: model.path)
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
        firstPersonRig()
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
        if actor == PlayerBody.actorFormID {
            return playerFace()
        }
        return game.renderer?.scene.faceMorphPlayback(for: actor)
    }

    var faceMorphPlaybacks: [FaceMorphPlayback] {
        let scene = game.renderer?.scene.animations.compactMap { $0 as? FaceMorphPlayback }
        return (scene ?? []) + [playerFace()].compactMap(\.self)
    }

    func faceMood(of actor: FormID) -> FaceMoodInput {
        let key = actor == PlayerBody.actorFormID
            ? ReferenceKey.player : game.streamer?.referenceEntry(formID: actor)?.key
        guard let key else { return .calm }
        let facts = key == .player
            ? game.combat.playerActionFacts : game.combat.loop?.phase(of: key)?.actionFacts
        let mood = game.actorWorld.actorValueHolder(for: key).flatMap { holder in
            game.actorValues.runtime?.value(at: Self.moodActorValue, on: holder)
        }
        // The player's face reads only its own draw and swing, an NPC's its combat.
        let swings = [ActorAttackState.draw, .swing].contains(facts?.attackState ?? .none)
        return FaceMoodInput(
            isFleeing: facts?.isFleeing == true,
            isInCombat: key != .player && game.actorWorld.isInCombat(key),
            isAttacking: key == .player && swings,
            mood: mood.map { Int($0) } ?? 0
        )
    }

    /// `Mood`, actor value 4.
    private static let moodActorValue: Int32 = 4
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
