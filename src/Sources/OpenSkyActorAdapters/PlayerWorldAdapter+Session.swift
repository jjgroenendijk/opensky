// `PlayerWorldAdapter` built over the started session: it registers its frame steps and
// session events as it is built (docs/decisions/session-scope.md).

import OpenSkyActorPresentation
import OpenSkyActors
import OpenSkyActorsInterface
import OpenSkyCells
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkySessionInterface
public import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

extension PlayerWorldAdapter {
    /// Without a stage, as in a test, it registers nothing.
    public convenience init(
        game: some PlayerWorldHosts,
        stage: SessionStage?
    ) {
        self.init(game: game)
        guard let stage else { return }
        registerPlayerBody(stage: stage)
        registerPlayerActorState(stage: stage)
    }

    private func registerPlayerBody(stage: SessionStage) {
        let gameSession = stage.gameSession
        gameSession.assetDrains.register(.playerBody) { [weak game = self.game] _ in
            game?.player.drainClipLoads()
        }
        gameSession.frameSteps.register(.playerBody) { [weak game = self.game] _ in
            game?.player.refreshBody()
        }
    }

    private func registerPlayerActorState(stage: SessionStage) {
        let gameSession = stage.gameSession
        let game = game
        gameSession.frameSteps.register(.actorState) { [weak game, weak gameSession] _ in
            guard let game, let locomotion = gameSession?.locomotion else { return }
            locomotion.actorState = PlayerActorStateReader(game: game)
                .inputs(from: locomotion.actorState)
        }
    }
}

/// The player's combat, keyword, weight, casting, and voice inputs of the actor-state graph.
struct PlayerActorStateReader {
    let game: any PlayerWorldHost

    func inputs(from current: ActorStateGraphInputs) -> ActorStateGraphInputs {
        var inputs = current
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
            .face.weight ?? ResolvedActorAppearance.defaultWeight
        inputs.isBowDrawn = game.combat.archery?.state.phase.isFullyDrawn ?? false
        inputs.castingLeft = game.magic.wantsCast(.left)
        inputs.castingRight = game.magic.wantsCast(.right)
        inputs.wantsVoice = game.magic.shoutMachine.wantsVoice
        inputs.headTracking = game.headTracking.isEnabled
        return inputs
    }
}
