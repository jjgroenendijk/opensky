// The Papyrus natives `ScriptPerkBindingsAdapter` fills as the bridge is built.

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

extension ScriptPerkBindingsAdapter {
    /// Fills these natives as the bridge is built.
    public func fillPerkNatives(bridge: PapyrusWorldStateBridge) {
        bridge.natives.progression
            .mutatePerks = { [weak game = self.game] mutation, perk, actor in
                guard let game, let holder = game.actorWorld.actorValueHolder(for: actor) else {
                    return false
                }
                return switch mutation {
                case .add: game.perks.add(perk, to: holder)
                case .remove: game.perks.remove(perk, from: holder)
                }
            }
        bridge.natives.progression.perkOwnership = { [weak game = self.game] key in
            game?.perks.ownership(of: key)
        }
        bridge.natives.progression
            .advanceSkill = { [weak game = self.game] advance, index, magnitude in
                guard let progression = game?.progression else { return false }
                return switch advance {
                case .advance: progression.advanceSkill(index, byUse: magnitude)
                case .increment: progression.incrementSkill(index)
                }
            }
        // A zero delta is the read `Game.GetPerkPoints` makes.
        bridge.natives.progression.modifyPerkPoints = { [weak game = self.game] delta in
            game?.progression.modifyPerkPoints(by: delta)
        }
        bridge.natives.crime.crimeReporter = { [weak game = self.game] in game?.crime.reporter }
        bridge.natives.crime.arrestSession = { [weak game = self.game] in game?.crime }
        game.crime
            .scriptedOwner = { [weak bridge] key in bridge?.stateLinks.scriptedOwner(of: key) }
        let worldState = game.worldState
        game.crime.scriptedOwnerRevision = { [weak worldState] in
            worldState?.revision(of: [.scriptedState]) ?? 0
        }
        bridge.natives.crime.showBarterMenu = { [weak game = self.game] actor in
            guard let game, game.inventory.vendors != nil else { return nil }
            let text = game.containerMenu.openBarter(with: actor)
            return (game.containerMenu.isOpen && game.containerMenu.vendor != nil, text)
        }
        bridge.natives.faction = game.factionWorld.papyrusNatives()
        bridge.scriptState.publishFactionReactions()
    }
}
