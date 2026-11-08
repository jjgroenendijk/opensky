// `ScriptActorBindingsAdapter` joins the started session: what `wireActorNatives` registered.

import OpenSkyActorPresentation
import OpenSkyActors
import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyCrime
import OpenSkyEffects
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyMagic
import OpenSkyMagicInterface
import OpenSkyMenus
import OpenSkyMenusInterface
import OpenSkyPerception
import OpenSkyPerceptionInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyProgression
import OpenSkyQuests
import OpenSkyQuestsInterface
import OpenSkyRendering
import OpenSkyRuntimeState
public import OpenSkyScripting
import OpenSkyScriptingInterface
import OpenSkySessionInterface
import OpenSkyWeather
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// Getters, not captured values: the runtimes behind them are wired after
/// this step.
public struct ScriptActorNativesWiring {
    public init(_ adapter: ScriptActorBindingsAdapter, bridge: PapyrusWorldStateBridge) {
        bridge.actorNatives
            .actorValueRuntime = { [weak game = adapter.game] in game?.actorValues.runtime }
        bridge.actorNatives.ragdollRuntime = { [weak game = adapter.game] in game?.ragdoll.runtime }
        bridge.actorNatives.combatRuntime = { [weak game = adapter.game] in game?.combat.loop }
        // Only the player tracks a draw state, so `IsWeaponDrawn` fails with a
        // reason for everyone else instead of claiming sheathed.
        bridge.actorNatives.weaponDrawState = { [weak game = adapter.game] key in
            guard key == .player else { return nil }
            return game?.combat.melee?.state.drawState
        }
        bridge.sessionNatives.conditionData = { [weak game = adapter.game] in
            game?.runtimeStateWorld.conditionData() ?? .empty
        }
        bridge.perceptionNatives
            .detection = { [weak game = adapter.game] in game?.perception.perceptionResolution() }
        bridge.sessionNatives.currentPackage = { [weak game = adapter.game] actor in
            game?.packages.runtime?.currentPackage(for: actor)?.package.formID
        }
        bridge.sessionNatives
            .packageTemplate = { [weak game = adapter.game] package in
                game?.packages.template(of: package)
            }
        bridge.perceptionNatives.lightLevel = { [weak game = adapter.game] feet in
            let body = SIMD3<Float>(0, 0, PlayerCapsule.standard.torsoHeight)
            return game?.aiWorld.lightLevel(at: feet + body) ?? 1
        }
        bridge.sessionNatives.cellFog = { [weak owner = adapter.owner] cell, change in
            owner?.skyBindings.changeFog(change, in: cell) ?? false
        }
        bridge.sessionNatives.havokMass = { [weak game = adapter.game] key in
            if let body = game?.streamer?.dynamicBodies.body(for: key) {
                return body.definition.mass
            }
            return game?.ragdoll.runtime?.world.ragdolls.first { $0.key == key }?
                .instance.bodies.reduce(0) { $0 + $1.definition.mass }
        }
        let owner = adapter.owner
        bridge.sessionNatives.publishTranslationPoses = { [weak owner, weak bridge] poses in
            owner?.physicsBindings.publishTranslations(poses, moves: bridge?.translations ?? [:])
        }
        bridge.perceptionNatives.livePosition = { [weak game = adapter.game] key in
            guard let game else { return nil }
            guard key != .player else { return game.gameSession?.locomotion.status.feetPosition }
            return game.actorWorld.combatActor(key: key)?.feet
        }
    }
}
