// App side of `PlayerCoordinator` and `FaceMorphCoordinator`: answers their
// ports from the live renderer, the inventory, and the dialogue menu. The rules
// live in the coordinators (docs/engine/coordinators.md).

import OpenSkyActorsInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyRendering
import OpenSkyWorld
import OpenSkyWorldState

/// Answers `PlayerWorld` and `FaceMorphWorld` from the session systems `game` owns.
final class PlayerWorldAdapter {
    unowned let game: GameViewController

    init(game: GameViewController) {
        self.game = game
    }

    /// The graph and the body outlive every cell, so this is not streaming.
    func wirePlayerBody(session: CellSession, renderer: Renderer) {
        let player = game.player
        let source = PlayerRigQueue(
            runner: session.runner,
            fileSystem: (session.data as? ScriptDataProviding)?.scriptFileSystem
        )
        guard player.wireBody(source: source) else { return }
        renderer.session.assetDrains.add { [weak player] _ in
            player?.drainClipLoads()
        }
        renderer.onFrame.add { [weak player] _ in
            player?.refreshBody()
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
        game.renderer?.locomotion
    }

    var isWalkModeActive: Bool {
        game.renderer?.movementMode.isPlayerControlled ?? false
    }

    var isPlayerGrounded: Bool {
        game.renderer?.walkController.isGrounded ?? true
    }

    var playerEquippedSet: [FormID]? {
        guard
            let equipment = game.inventory.equipment,
            equipment.inventory.hasRuntimeInventory(InventoryHolder.player)
        else { return nil }
        return equipment.equipped(on: InventoryHolder.player)
    }

    var playerAppearanceOverride: PlayerAppearanceOverride? {
        game.worldState.component(PlayerIdentityState.self, for: .player).map { identity in
            var appearance = PlayerAppearanceOverride(
                race: identity.race, isFemale: identity.isFemale,
                headParts: identity.face.headParts, hairColor: identity.face.hairColor
            )
            appearance.faceMorphs = identity.face.morphs
            appearance.faceParts = identity.face.parts
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
        try game.renderer?.setPlayerBody(body)
    }

    func showFirstPersonRig(_ rig: PlayerFirstPersonRig) throws {
        try game.renderer?.setPlayerFirstPersonRig(rig)
    }

    var playerFirstPersonRig: PlayerFirstPersonRig? {
        game.renderer?.playerFirstPersonRig
    }

    var areFirstPersonArmsVisible: Bool {
        game.renderer?.areFirstPersonArmsVisible ?? false
    }

    var firstPersonFOVYRadians: Float? {
        game.renderer?.firstPersonCamera.fovYRadians
    }

    func setFirstPersonFOVY(radians: Float) {
        game.renderer?.setFirstPersonFOVY(radians: radians)
    }

    var firstPersonArmsEnabled: Bool? {
        game.renderer?.firstPersonArmsEnabled
    }

    func setFirstPersonArmsEnabled(_ enabled: Bool) {
        game.renderer?.firstPersonArmsEnabled = enabled
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
}
