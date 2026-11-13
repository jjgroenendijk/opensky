import Foundation
import OpenSkyCells
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
public import OpenSkyMagicInterface
public import OpenSkyMenus
public import OpenSkyMenusInterface
public import OpenSkySessionInterface

/// What `MenuScreensGiftListsAdapter` reads from the session.
@MainActor
public protocol MenuScreensGiftListsHost: AnyObject, SendableMetatype {
    var actorWorld: any ActorWorldPort { get }
    var inventory: any InventoryPort { get }
    var inventoryWorld: any InventoryWorldPort { get }
    var magic: any MagicPort { get }
    var streamer: any CellStreamerPort { get }
    var menuRecords: (any MenuRecordsPort)? { get }
    var mapWorld: any MapWorldPort { get }
}

/// Part of `MenuScreensWorldAdapter`, over its own narrow host.
public struct MenuScreensGiftListsAdapter {
    public let game: any MenuScreensGiftListsHost
}

extension MenuScreensGiftListsAdapter {
    /// "All" first, then one tab per spell kind in the order the kinds first appear.
    /// All, then one tab per school, shouts, and powers in the menu's order, then the
    /// effects on the player. A tab with no rows is left out.
    var magicMenuCategories: [ItemListCategory] {
        let menu = game.magic.magicMenu
        let spells = menu.magicMenuSpells.enumerated().map { index, spell in
            (category: spell.category, row: ItemListRow(
                tag: UInt32(index), name: spell.name, isEquipped: spell.isReadied
            ))
        }
        let shouts = menu.magicMenuShouts.enumerated().map { index, shout in
            (category: shout.category, row: ItemListRow(
                tag: UInt32(Self.shoutTagBase + index), name: shout.name,
                isEquipped: shout.isReadied
            ))
        }
        let order = menu.magicMenuCategoryOrder
        let tabs = order.compactMap { title -> ItemListCategory? in
            let rows = (spells + shouts).filter { $0.category == title }.map(\.row)
            return rows.isEmpty ? nil : ItemListCategory(label: title, rows: rows)
        }
        let effects = menu.magicMenuActiveEffects.enumerated().map { index, name in
            ItemListRow(tag: UInt32(spells.count + index), name: name)
        }
        let effectsTab = effects.isEmpty
            ? []
            : [ItemListCategory(label: menu.magicMenuActiveEffectsTitle, rows: effects)]
        let all = ItemListCategory(label: "All", rows: (spells + shouts).map(\.row))
        return [all] + tabs + effectsTab
    }

    /// Shout rows carry tags from here on, past any spell or effect row.
    static let shoutTagBase = 1 << 20

    public func readySpell(at index: Int, leftHand: Bool) -> String {
        if index >= Self.shoutTagBase {
            return game.magic.magicMenu.readyShout(
                at: index - Self.shoutTagBase, texts: game.mapWorld.settingTexts()
            )
        }
        return game.magic.menuLines.readyKnownSpellLine(at: index, in: leftHand ? .left : .right)
    }

    public func shoutUnlockStep(at index: Int) -> ShoutUnlockStep? {
        guard index >= Self.shoutTagBase else { return nil }
        return game.magic.magicMenu.shoutUnlockStep(
            at: index - Self.shoutTagBase, texts: game.mapWorld.settingTexts()
        )
    }

    public func unlockShout(at index: Int) -> String {
        game.magic.magicMenu.unlockShout(at: index - Self.shoutTagBase)
    }
}

extension MenuScreensGiftListsAdapter {
    var nearestActor: ReferenceKey? {
        game.actorWorld.nearestActorValueHolder()?.key
    }

    public func giftCategories(
        actor: ReferenceKey,
        request: GiftMenuRequest
    ) -> [ItemListCategory] {
        guard
            let runtime = game.inventory.runtime?.inventory,
            let giver = request.giving ? .player : game.streamer.residents
                .inventoryHolder(of: actor)
        else { return [] }
        let rows = runtime.inventory(of: giver).stacks
            .filter { $0.item != runtime.goldFormID }
            .filter { request.shows(stolen: $0.stolen, identities: giftIdentities(of: $0.item)) }
            .map { stack in
                ItemListRow(
                    tag: stack.item.rawValue, name: game.inventory.name(of: stack.item),
                    count: stack.count
                )
            }
            .sorted { $0.name < $1.name }
        return [ItemListCategory(label: "All", rows: rows)]
    }

    /// The item and its keywords as form list entries, for a gift filter.
    private func giftIdentities(of item: FormID) -> Set<ReferenceKey> {
        guard
            let data = game.menuRecords, let lists = data.formListStore,
            let plugin = data.magicItemPluginName
        else { return [] }
        let keywords = game.inventoryWorld.itemKeywords(of: item) ?? []
        return Set(([item] + keywords).compactMap {
            lists.resolvedID($0, fromPlugin: plugin).map(ReferenceKey.init(resolved:))
        })
    }

    /// A gift past the receiver's `CarryWeight`, as the game greys its row.
    public func giftRefusal(_ item: FormID, actor: ReferenceKey, giving: Bool) -> String? {
        guard
            giving,
            let other = game.streamer.residents.inventoryHolder(of: actor),
            game.inventory.teammateTrades.teammateRefusal(
                .store, item: item, count: 1, teammate: other
            ) == .overencumbered
        else { return nil }
        return game.mapWorld.settingTexts(TeammateTradeText.self)[.itemTooHeavy]
    }

    public func give(_ item: FormID, actor: ReferenceKey, giving: Bool) -> String {
        guard
            let runtime = game.inventory.runtime?.inventory,
            let other = game.streamer.residents.inventoryHolder(of: actor)
        else { return "No inventory" }
        let name = game.inventory.name(of: item)
        do {
            try runtime.transfer(
                item, count: 1, from: giving ? .player : other, to: giving ? other : .player
            )
            return giving ? "Gave \(name)" : "Received \(name)"
        } catch {
            return "Not moved: \(error)"
        }
    }
}
