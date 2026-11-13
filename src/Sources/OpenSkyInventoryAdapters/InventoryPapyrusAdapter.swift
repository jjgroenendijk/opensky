import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyConditions
import OpenSkyCrimeInterface
import OpenSkyFactionsInterface
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
public import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyMenusInterface
import OpenSkyPerceptionInterface
import OpenSkyPlayer
import OpenSkyProgressionInterface
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScriptingInterface
import OpenSkySessionInterface
import OpenSkyWorldConditions
import OpenSkyWorldInterface
import OpenSkyWorldState

/// Part of `InventoryWorldAdapter`, over its own narrow host.
public struct InventoryPapyrusAdapter {
    public let game: any InventoryCommandsHost
}

extension InventoryPapyrusAdapter {
    public func addItem(_ item: FormID, count: Int32, to holder: ReferenceKey) -> Bool {
        game.inventory.scriptItems.scriptAddItem(item, count: count, to: holder)
    }

    public func removeItem(
        _ item: FormID, count: Int32, from holder: ReferenceKey, to other: ReferenceKey?
    ) -> Bool {
        InventoryCommandRunner(game: game).run(game.inventory.scriptItems.scriptRemoveItem(
            item,
            count: count,
            from: holder,
            to: other
        ))
    }

    public func unequipSlot(_ slot: Int32, on actor: ReferenceKey) -> Bool {
        InventoryCommandRunner(game: game).run(game.inventory.scriptItems.scriptUnequipSlot(
            slot,
            on: actor
        ))
    }

    public func dropItem(_ item: FormID, count: Int32, from holder: ReferenceKey) -> ReferenceKey? {
        InventoryCommandRunner(game: game).run(game.inventory.scriptItems.scriptDropObject(
            item,
            count: count,
            from: holder
        ))
    }

    public func removeAllItems(
        from holder: ReferenceKey, to other: ReferenceKey?, removeQuestItems: Bool
    ) -> Bool {
        InventoryCommandRunner(game: game).run(game.inventory.scriptItems.scriptRemoveAllItems(
            from: holder, to: other, removeQuestItems: removeQuestItems
        ))
    }

    public func baselineInventory(of holder: ReferenceKey) -> ReferenceInventoryState? {
        game.inventory.scriptItems.scriptBaselineInventory(of: holder)
    }

    public func itemCount(_ item: FormID, in holder: ReferenceKey) -> Int32? {
        game.inventory.scriptItems.scriptItemCount(item, in: holder)
    }

    public func equipItem(_ item: FormID, on actor: ReferenceKey) -> Bool {
        InventoryCommandRunner(game: game).run(game.inventory.scriptItems.scriptEquipItem(
            item,
            on: actor
        ))
    }

    public func unequipItem(_ item: FormID, on actor: ReferenceKey) -> Bool {
        InventoryCommandRunner(game: game).run(game.inventory.scriptItems.scriptUnequipItem(
            item,
            on: actor
        ))
    }

    public func setOutfit(_ outfit: FormID, on actor: ReferenceKey) -> Bool {
        InventoryCommandRunner(game: game).run(game.inventory.scriptItems.scriptSetOutfit(
            outfit,
            on: actor
        ))
    }

    public func isEquipped(_ item: FormID, on actor: ReferenceKey) -> Bool? {
        game.inventory.scriptItems.scriptIsEquipped(item, on: actor)
    }

    public func equippedWeapon(on actor: ReferenceKey, leftHand: Bool) -> FormID?? {
        game.inventory.scriptItems.scriptEquippedWeapon(on: actor, leftHand: leftHand)
    }

    public func equippedShield(on actor: ReferenceKey) -> FormID?? {
        game.inventory.scriptItems.scriptEquippedShield(on: actor)
    }

    public func unequipAll(on actor: ReferenceKey) -> Bool {
        InventoryCommandRunner(game: game)
            .run(game.inventory.scriptItems.scriptUnequipAll(on: actor))
    }

    public func goldValue(of item: FormID) -> Int32? {
        game.inventory.scriptItems.scriptGoldValue(of: item)
    }

    public func learnIngredientEffects(_ ingredient: FormID, indices: [Int]?) -> Bool {
        game.inventory.alchemyLab.learnIngredientEffects(ingredient, indices: indices)
    }

    public func learnNextIngredientEffect(_ ingredient: FormID) -> Int? {
        game.inventory.alchemyLab.learnNextIngredientEffect(ingredient)
    }

    public func isHostileItem(_ item: FormID) -> Bool? {
        game.inventory.alchemyLab.isHostileItem(item)
    }
}
