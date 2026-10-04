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
    func wirePlayerBody(provider: any WorldDataProviding, renderer: Renderer) {
        let player = game.player
        guard player.wireBody(provider: provider) else { return }
        renderer.session.assetDrains.add { [weak player] _ in
            player?.drainClipLoads()
        }
        renderer.onFrame.add { [weak player] _ in
            player?.refreshBody()
        }
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
        game.worldState.component(PlayerIdentityState.self, for: .player).map {
            PlayerAppearanceOverride(
                race: $0.race, isFemale: $0.isFemale, headParts: $0.face.headParts,
                hairColor: $0.face.hairColor
            )
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
