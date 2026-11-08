import OpenSkyActors
import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyConditions
import OpenSkyCrime
import OpenSkyCrimeInterface
import OpenSkyFactions
import OpenSkyFactionsInterface
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
public import OpenSkyInventoryInterface
import OpenSkyMagic
import OpenSkyMagicInterface
import OpenSkyMenus
import OpenSkyMenusInterface
import OpenSkyPerception
import OpenSkyPerceptionInterface
import OpenSkyPlayer
import OpenSkyProgression
import OpenSkyProgressionInterface
import OpenSkyQuests
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScripting
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldConditions
import OpenSkyWorldInterface
import OpenSkyWorldState

/// What `InventoryPapyrusAdapter` reads from the session.
@MainActor
public protocol InventoryPapyrusHost: AnyObject {
    var inventory: any InventoryPort { get }
}

/// Part of `InventoryWorldAdapter`, over its own narrow host.
public struct InventoryPapyrusAdapter {
    public unowned let owner: InventoryWorldAdapter
    public unowned let game: any InventoryPapyrusHost
}

extension InventoryPapyrusAdapter {
    public func addItem(_ item: FormID, count: Int32, to holder: ReferenceKey) -> Bool {
        game.inventory.scriptAddItem(item, count: count, to: holder)
    }

    public func removeItem(
        _ item: FormID, count: Int32, from holder: ReferenceKey, to other: ReferenceKey?
    ) -> Bool {
        owner.run(game.inventory.scriptRemoveItem(item, count: count, from: holder, to: other))
    }

    public func unequipSlot(_ slot: Int32, on actor: ReferenceKey) -> Bool {
        owner.run(game.inventory.scriptUnequipSlot(slot, on: actor))
    }

    public func dropItem(_ item: FormID, count: Int32, from holder: ReferenceKey) -> ReferenceKey? {
        owner.run(game.inventory.scriptDropObject(item, count: count, from: holder))
    }

    public func removeAllItems(
        from holder: ReferenceKey, to other: ReferenceKey?, removeQuestItems: Bool
    ) -> Bool {
        owner.run(game.inventory.scriptRemoveAllItems(
            from: holder, to: other, removeQuestItems: removeQuestItems
        ))
    }

    public func baselineInventory(of holder: ReferenceKey) -> ReferenceInventoryState? {
        game.inventory.scriptBaselineInventory(of: holder)
    }

    public func itemCount(_ item: FormID, in holder: ReferenceKey) -> Int32? {
        game.inventory.scriptItemCount(item, in: holder)
    }

    public func equipItem(_ item: FormID, on actor: ReferenceKey) -> Bool {
        owner.run(game.inventory.scriptEquipItem(item, on: actor))
    }

    public func unequipItem(_ item: FormID, on actor: ReferenceKey) -> Bool {
        owner.run(game.inventory.scriptUnequipItem(item, on: actor))
    }

    public func setOutfit(_ outfit: FormID, on actor: ReferenceKey) -> Bool {
        owner.run(game.inventory.scriptSetOutfit(outfit, on: actor))
    }

    public func isEquipped(_ item: FormID, on actor: ReferenceKey) -> Bool? {
        game.inventory.scriptIsEquipped(item, on: actor)
    }

    public func equippedWeapon(on actor: ReferenceKey, leftHand: Bool) -> FormID?? {
        game.inventory.scriptEquippedWeapon(on: actor, leftHand: leftHand)
    }

    public func equippedShield(on actor: ReferenceKey) -> FormID?? {
        game.inventory.scriptEquippedShield(on: actor)
    }

    public func unequipAll(on actor: ReferenceKey) -> Bool {
        owner.run(game.inventory.scriptUnequipAll(on: actor))
    }

    public func goldValue(of item: FormID) -> Int32? {
        game.inventory.scriptGoldValue(of: item)
    }

    public func learnIngredientEffects(_ ingredient: FormID, indices: [Int]?) -> Bool {
        game.inventory.learnIngredientEffects(ingredient, indices: indices)
    }

    public func learnNextIngredientEffect(_ ingredient: FormID) -> Int? {
        game.inventory.learnNextIngredientEffect(ingredient)
    }

    public func isHostileItem(_ item: FormID) -> Bool? {
        game.inventory.isHostileItem(item)
    }
}
