// The Papyrus natives `ScriptActorBindingsAdapter` fills as the bridge is built.

import OpenSkyActorPresentation
import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyEffects
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface
import OpenSkyMenusInterface
import OpenSkyPerceptionInterface
import OpenSkyPhysics
import OpenSkyPlayer
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

extension ScriptActorBindingsAdapter {
    /// Fills these natives as the bridge is built.
    public func fillActorNatives(bridge: PapyrusWorldStateBridge) {
        bridge.natives.actor
            .actorValueRuntime = { [weak game = self.game] in game?.actorValues.runtime }
        bridge.natives.actor.ragdollRuntime = { [weak game = self.game] in game?.ragdoll.runtime }
        bridge.natives.actor.combatRuntime = { [weak game = self.game] in game?.combat.loop }
        // Only the player tracks a draw state, so `IsWeaponDrawn` fails with a
        // reason for everyone else instead of claiming sheathed.
        bridge.natives.actor.weaponDrawState = { [weak game = self.game] key in
            guard key == .player else { return nil }
            return game?.combat.melee?.state.drawState
        }
        bridge.natives.session.conditionData = { [weak game = self.game] in
            game?.runtimeStateWorld.conditionData() ?? .empty
        }
        bridge.natives.perception
            .detection = { [weak game = self.game] in game?.perception.perceptionResolution() }
        bridge.natives.session.currentPackage = { [weak game = self.game] actor in
            game?.packages.runtime?.currentPackage(for: actor)?.package.formID
        }
        bridge.natives.session
            .packageTemplate = { [weak game = self.game] package in
                game?.packages.template(of: package)
            }
        bridge.natives.perception.lightLevel = { [weak game = self.game] feet in
            let body = SIMD3<Float>(0, 0, PlayerCapsule.standard.torsoHeight)
            return game?.aiWorld.lightLevel(at: feet + body) ?? 1
        }
        bridge.natives.session.cellFog = { [sky = self.skyBindings] cell, change in
            sky.changeFog(change, in: cell)
        }
        bridge.natives.session.havokMass = { [weak game = self.game] key in
            if let body = game?.streamer.dynamicBodies.body(for: key) {
                return body.definition.mass
            }
            return game?.ragdoll.runtime?.world.ragdolls.first { $0.key == key }?
                .instance.bodies.reduce(0) { $0 + $1.definition.mass }
        }
        let physics = physicsBindings
        bridge.natives.session.publishTranslationPoses = { [weak bridge] poses in
            physics.publishTranslations(poses, moves: bridge?.runState.translations ?? [:])
        }
        bridge.natives.perception.livePosition = { [weak game = self.game] key in
            guard let game else { return nil }
            guard key != .player else { return game.gameSession?.locomotion.status.feetPosition }
            return game.actorWorld.combatActor(key: key)?.feet
        }
    }
}
