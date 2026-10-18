// The live seams every condition context carries besides the feature ones:
// script variables, scenes, weather, and the player's inventory.

import Foundation
import OpenSkyActorPresentation
import OpenSkyActors
import OpenSkyActorsInterface
import OpenSkyAIPackages
import OpenSkyConditions
import OpenSkyDialogue
import OpenSkyDialogueInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyMenus
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyQuestsInterface
import OpenSkyScripting
import OpenSkyScriptingInterface
import OpenSkyWeather
import OpenSkyWorld
import OpenSkyWorldConditions
import OpenSkyWorldInterface
import OpenSkyWorldState

extension RuntimeStateWorldAdapter {
    func addLiveSeams(to context: inout ConditionContext) {
        context.scriptVariables = game.scripts.runtime?.scriptVariableResolution() ?? .empty
        context.scriptedState = game.scripts.bridge?.scriptedStateResolution() ?? .empty
        context.scenes = game.scenes.conditionResolution(aliases: context.aliases)
        context.weather = weatherResolution()
        context.furniture = game.idleWorld.idles.furnitureResolution
        if let inventory = inventoryResolution(context: context) {
            context.inventory = inventory
        }
        context.referenceFacts = referenceFacts(of: context.references)
        context.motion = motionResolution(references: context.references)
        context.places = placeResolution(references: context.references)
        let vehicles = game.vehicleWorld.vehicles
        context.mounts = MountConditionResolution(
            mounts: vehicles.core.mounts, playersLastMount: vehicles.playersLastMount
        )
        context.menus = MenuConditionResolution(
            isMenuOpen: game.menuMode.topMenu != nil,
            isLoading: game.menuMode.topMenu == LoadingScreenWorldAdapter.identifier
        )
        context.dialogue = DialogueResolution(
            speakerInDialogue: game.dialogue.conversationSpeaker, line: game.dialogue.spokenLine
        )
        context.packages = game.packages.runtime?.conditionResolution { location, actor in
            game.aiWorld.isWithin(location, actor: actor)
        } ?? .empty
    }

    /// Lock, open, and deletion state of every reference a run-on can name.
    private func referenceFacts(of references: RuntimeReferenceIndex)
        -> ReferenceConditionResolution
    {
        var facts: [ReferenceKey: ReferenceConditionFacts] = [:]
        for entry in references.sortedEntries() {
            let state = game.worldState.resolvedState(for: entry)
            facts[entry.key] = ReferenceConditionFacts(
                lock: ReferenceLockState.resolve(
                    baseline: entry.placedReference?.lock,
                    delta: game.worldState.component(ReferenceLockState.self, for: entry.key)
                ),
                isOpen: state.activation.isOpen,
                isDoor: game.streamer?.residentInteraction(reference: entry.formID)?
                    .action == .open,
                isDeleted: state.deletion.isDeleted
            )
        }
        return ReferenceConditionResolution(facts: facts)
    }

    private func weatherResolution() -> WeatherConditionResolution {
        guard
            let weather = game.gameSession?.weather,
            let current = weather.currentWeatherID
        else { return .empty }
        return WeatherConditionResolution(
            weather: current,
            precipitation: weather.store.weather(current)?.data?.precipitation ?? .none
        )
    }

    /// The player's item counts, and the equipment of the player and every actor a
    /// run-on can name. Any other holder is read on demand through the lookup.
    private func inventoryResolution(context: ConditionContext) -> InventoryConditionResolution? {
        guard let runtime = game.inventory.runtime else { return nil }
        let stacks = runtime.inventory.inventory(of: runtime.player).stacks
        let equipped = game.inventory.equipment?.equipped(on: runtime.player) ?? []
        var equipment: [ReferenceKey: ActorEquipmentFacts] = [:]
        for key in [.player] + context.references.sortedActorEntries.map(\.key) {
            guard var facts = game.inventory.conditionEquipment(of: key) else { continue }
            let spells = context.magic.state(of: key)?.handSpells ?? [:]
            facts.rightHandType = Self.handType(facts.rightWeapon, spell: spells[.right] != nil)
            facts.leftHandType = facts.hasShield && facts.leftWeapon == nil
                ? CombatHandType.shield.rawValue
                : Self.handType(facts.leftWeapon, spell: spells[.left] != nil)
            equipment[key] = facts
        }
        return InventoryConditionResolution(
            counts: [.player: stacks.reduce(into: [:]) { $0[$1.item, default: 0] += $1.count }],
            equipped: [.player: Set(equipped)],
            equipment: equipment,
            keywordCounts: [.player: game.inventory.conditionKeywordCounts(of: .player) ?? [:]],
            lookup: inventoryLookup()
        )
    }

    /// Conditions run on the main actor, as the whole simulation does.
    private func inventoryLookup() -> InventoryConditionLookup {
        let inventory = game.inventory
        return InventoryConditionLookup(
            count: { [weak inventory] item, holder in
                MainActor.assumeIsolated { inventory?.scriptItemCount(item, in: holder) }
            },
            isEquipped: { [weak inventory] item, holder in
                MainActor.assumeIsolated { inventory?.scriptIsEquipped(item, on: holder) }
            },
            keywordCounts: { [weak inventory] holder in
                MainActor.assumeIsolated { inventory?.conditionKeywordCounts(of: holder) }
            }
        )
    }

    private static func handType(_ weapon: EquippedWeaponFacts?, spell: Bool) -> Int32 {
        if let weapon {
            return CombatHandType(weapon: weapon.animationType).rawValue
        }
        return spell ? CombatHandType.spell.rawValue : CombatHandType.handToHand.rawValue
    }

    /// Nil without an inventory or actor values, which `IsOverEncumbered` reports.
    func playerIsOverEncumbered() -> Bool? {
        guard
            game.inventory.runtime != nil,
            let capacity = game.actorValues.runtime?.value(
                at: ActorValueIdentity.carryWeightIndex, on: .player
            )
        else { return nil }
        return FastTravelRule.isOverencumbered(
            carried: game.inventory.playerCarriedWeight, capacity: capacity
        )
    }

    /// The player's sex and race from the race menu, and the gait the walk uses.
    func playerConditionTraits(_ state: inout ActorConditionState) {
        if let identity = game.menuWorld.playerIdentity {
            state.isFemale = identity.isFemale
            state.race = identity.race
        }
        let gait = game.gameSession?.locomotion.status.gait
        state.isSneaking = gait.map { $0 == .sneak }
        state.isSprinting = gait.map { $0 == .sprint }
        state.isSwimming = gait.map { $0 == .swim }
    }
}
