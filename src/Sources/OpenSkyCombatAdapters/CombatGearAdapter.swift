import OpenSkyActorPresentation
import OpenSkyActorsInterface
import OpenSkyAIPackages
import OpenSkyAudio
import OpenSkyBehavior
import OpenSkyCells
import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyCrimeInterface
import OpenSkyDialogueInterface
import OpenSkyFactionsInterface
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyGameData
public import OpenSkyInventoryInterface
public import OpenSkyMagicInterface
import OpenSkyNavigation
import OpenSkyPerceptionInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyProgressionInterface
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// What `CombatGearAdapter` reads from the session.
@MainActor
public protocol CombatGearHost: AnyObject {
    var inventory: any InventoryPort { get }
    var magic: any MagicPort { get }
    var streamer: any CellStreamerPort { get }
}

/// Part of `CombatWorldAdapter`, over its own narrow host.
public struct CombatGearAdapter {
    public let game: any CombatGearHost
}

extension CombatGearAdapter {
    public var equipment: (any EquipmentAccess)? {
        game.inventory.equipment
    }

    public func magicInfluence(of key: ReferenceKey) -> ActorMagicInfluence {
        game.magic.influence(of: key)
    }

    public func enchantmentProfile(of item: FormID) -> ItemEnchantmentProfile? {
        game.magic.enchantmentProfile(of: item, on: .player)
    }

    public func temperLevel(of item: FormID) -> Int32 {
        guard let runtime = game.inventory.runtime else { return 0 }
        return runtime.inventory.temperLevel(of: item, in: runtime.player)
    }

    public func equippedItems(of key: ReferenceKey) -> [(item: FormID, temperLevel: Int32)] {
        guard
            let runtime = game.inventory.runtime,
            let equipment = game.inventory.equipment,
            let holder = key == .player ? runtime.player : game.streamer.inventoryHolder(of: key)
        else { return [] }
        return equipment.equipped(on: holder).map {
            ($0, runtime.inventory.temperLevel(of: $0, in: holder))
        }
    }

    public func hasReadiedSpell(in hand: SpellHand) -> Bool {
        game.magic.hasReadiedSpell(in: hand)
    }

    public func playerCarriedItems() -> [FormID] {
        guard let runtime = game.inventory.runtime else { return [] }
        return runtime.inventory.inventory(of: runtime.player).stacks.map(\.item)
    }

    @discardableResult
    public func addItem(_ item: FormID, count: Int32, to key: ReferenceKey) -> Bool {
        guard
            let runtime = game.inventory.runtime,
            let holder = game.streamer.inventoryHolder(of: key)
        else { return false }
        return attempt { try runtime.inventory.add(item, count: count, to: holder) } != nil
    }

    @discardableResult
    public func removeOneFromPlayer(_ item: FormID) -> Bool {
        guard let runtime = game.inventory.runtime else { return false }
        return attempt { try runtime.inventory.remove(item, count: 1, from: runtime.player) } != nil
    }
}
