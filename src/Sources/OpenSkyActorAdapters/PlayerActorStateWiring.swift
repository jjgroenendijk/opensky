// `PlayerWorldAdapter` joins the started session: what `wireActorState` registered.

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

/// Copies what combat, magic, and the head tracking setting report into the
/// actor-state graph inputs.
public struct PlayerActorStateWiring {
    public init(_ adapter: PlayerWorldAdapter, gameSession: GameSession) {
        let game = adapter.game
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
                .face.weight ?? ResolvedActorAppearance.defaultWeight
            inputs.isBowDrawn = game.combat.archery?.state.phase.isFullyDrawn ?? false
            inputs.castingLeft = game.magic.wantsCast(.left)
            inputs.castingRight = game.magic.wantsCast(.right)
            inputs.wantsVoice = game.magic.shoutMachine.wantsVoice
            inputs.headTracking = game.headTracking.isEnabled
            locomotion.actorState = inputs
        }
    }
}
