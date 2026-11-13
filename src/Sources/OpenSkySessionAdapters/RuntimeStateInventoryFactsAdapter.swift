import Foundation
import OpenSkyActorPresentation
public import OpenSkyActorsInterface
import OpenSkyAIPackages
public import OpenSkyConditions
import OpenSkyCrimeInterface
import OpenSkyDialogueInterface
import OpenSkyFormatsESM
import OpenSkyGameData
public import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyMenusInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyQuestsInterface
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWeather
import OpenSkyWorld
import OpenSkyWorldConditions
import OpenSkyWorldInterface
import OpenSkyWorldState

/// What `RuntimeStateInventoryFactsAdapter` reads from the session.
@MainActor
public protocol RuntimeStateInventoryFactsHost: AnyObject, SendableMetatype {
    var actorValues: any ActorValuePort { get }
    var gameSession: (any GameSessionPort)? { get }
    var inventory: any InventoryPort { get }
    var menuWorld: any MenuWorldPort { get }
}

/// Part of `RuntimeStateWorldAdapter`, over its own narrow host.
public struct RuntimeStateInventoryFactsAdapter {
    public let game: any RuntimeStateInventoryFactsHost
    public let state: RuntimeStatePartState

    /// The player's traits a condition reads: sex, race, and gait.
    public var playerTraits: PlayerTraits {
        PlayerTraits(game: game)
    }
}

extension RuntimeStateInventoryFactsAdapter {
    /// The player's item counts, and the equipment of the player and every actor a
    /// run-on can name. Any other holder is read on demand through the lookup.
    public func inventoryResolution(context: ConditionContext) -> InventoryConditionResolution? {
        guard let runtime = game.inventory.runtime else { return nil }
        let actors = [.player] + context.references.sortedActorEntries.map(\.key)
        let key = InventoryViewKey(
            runtime: ObjectIdentifier(runtime),
            writes: runtime.inventory.store.revision(of: [.inventory]),
            actors: actors,
            spellHands: actors.map { actor in
                context.magic.state(of: actor).map { Set($0.handSpells.keys) } ?? []
            },
            hasEquipment: game.inventory.equipment != nil
        )
        return state.conditionCaches.inventory.value(for: key) {
            freshInventoryResolution(context: context, runtime: runtime)
        }
    }

    private func freshInventoryResolution(
        context: ConditionContext, runtime: any WorldItemRuntimePort
    ) -> InventoryConditionResolution {
        let stacks = runtime.inventory.inventory(of: runtime.player).stacks
        let equipped = game.inventory.equipment?.equipped(on: runtime.player) ?? []
        var equipment: [ReferenceKey: ActorEquipmentFacts] = [:]
        for key in [.player] + context.references.sortedActorEntries.map(\.key) {
            guard var facts = game.inventory.itemConditions.conditionEquipment(of: key)
            else { continue }
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
            keywordCounts: [.player: game.inventory.itemConditions
                .conditionKeywordCounts(of: .player) ?? [:]],
            lookup: inventoryLookup()
        )
    }

    /// Conditions run on the main actor, as the whole simulation does.
    private func inventoryLookup() -> InventoryConditionLookup {
        let inventory = game.inventory
        return InventoryConditionLookup(
            count: { [weak inventory] item, holder in
                MainActor
                    .assumeIsolated { inventory?.scriptItems.scriptItemCount(item, in: holder) }
            },
            isEquipped: { [weak inventory] item, holder in
                MainActor
                    .assumeIsolated { inventory?.scriptItems.scriptIsEquipped(item, on: holder) }
            },
            keywordCounts: { [weak inventory] holder in
                MainActor
                    .assumeIsolated { inventory?.itemConditions.conditionKeywordCounts(of: holder) }
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
    public func playerIsOverEncumbered() -> Bool? {
        guard
            game.inventory.runtime != nil,
            let capacity = game.actorValues.runtime?.value(
                at: ActorValueIdentity.carryWeightIndex, on: .player
            )
        else { return nil }
        return FastTravelRule.isOverencumbered(
            carried: game.inventory.armourWeights.playerCarriedWeight, capacity: capacity
        )
    }
}

extension RuntimeStateInventoryFactsAdapter {
    /// The player's traits a condition reads, apart from the item facts.
    public struct PlayerTraits {
        let game: any RuntimeStateInventoryFactsHost

        /// The player's sex and race from the race menu, and the gait the walk uses.
        public func fill(_ state: inout ActorConditionState) {
            if let identity = game.menuWorld.playerIdentity {
                state.isFemale = identity.isFemale
                state.race = identity.race
            }
            let gait = game.gameSession?.locomotion.status.gait
            state.isSneaking = gait.map { $0 == .sneak }
            state.isSprinting = gait.map { $0 == .sprint }
            state.isSwimming = gait.map { $0 == .swim }
            state.isInDangerousWater = game.gameSession.map {
                $0.locomotion.status.lastPlan.water?.isDangerous ?? false
            }
        }
    }
}
