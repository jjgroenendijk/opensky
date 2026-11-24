// A follower's trade: its starting outfit stays with it, and it carries no more than
// its `CarryWeight`. UESP "Skyrim:Followers". See docs/engine/barter.md#a-followers-trade.

import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyGameData
public import OpenSkyInventoryInterface

/// What the rule knows about one item moving to or from a follower.
nonisolated public struct TeammateTradeFacts: Equatable, Sendable {
    /// The follower's carried weight before the move.
    public var carriedWeight: Float = 0
    /// The weight the move adds to the follower.
    public var addedWeight: Float = 0
    /// The follower's `CarryWeight`. Nil without actor values, which refuses nothing.
    public var capacity: Float?

    public init() {}
}

nonisolated public enum TeammateTradeRule {
    /// The refusal of moving `count` of an item, or nil to let it through. A take is never
    /// refused: the trade list hides the outfit's copies, and the game shows no message.
    public static func refusal(
        _ transfer: ContainerTransfer,
        count: Int32,
        _ facts: TeammateTradeFacts
    )
        -> TeammateTradeText?
    {
        switch transfer {
        case .take, .buy, .sell:
            nil
        case .store:
            facts.capacity.map { facts.carriedWeight + facts.addedWeight > $0 } == true
                ? .overencumbered : nil
        }
    }
}

extension InventoryCoordinator.TeammateTrades {
    /// The refusal of moving `count` of `item` to or from the follower `teammate`.
    public func teammateRefusal(
        _ transfer: ContainerTransfer, item: FormID, count: Int32, teammate: InventoryHolder
    ) -> TeammateTradeText? {
        guard let inventory = coordinator.runtime?.inventory else { return nil }
        var facts = TeammateTradeFacts()
        facts.carriedWeight = inventory.carriedWeight(of: teammate)
        facts.addedWeight = (inventory.baselines.items.definition(item)?.weight ?? 0) * Float(count)
        facts.capacity = coordinator.world.carryWeight(of: teammate.key)
        return TeammateTradeRule.refusal(transfer, count: count, facts)
    }

    /// Takes everything but the follower's starting outfit.
    public func takeAllFromTeammate(_ teammate: InventoryHolder) -> ItemActionOutcome {
        guard let runtime = coordinator.runtime else { return .unavailable }
        let session = ContainerSession(runtime: runtime, container: teammate)
        var moved: [InventoryStack] = []
        var seen: Set<FormID> = []
        do {
            for stack in runtime.inventory.inventory(of: teammate).stacks
                where seen.insert(stack.item).inserted
            {
                let carried = runtime.inventory.count(of: stack.item, in: teammate)
                let count = carried - outfitCount(of: stack.item, on: teammate)
                guard count > 0 else { continue }
                _ = try session.take(stack.item, count: count)
                moved.append(InventoryStack(item: stack.item, count: count))
            }
        } catch {
            return .failed(action: "Take all", reason: String(describing: error))
        }
        coordinator.containerTrade.reportTaken(moved, from: session)
        for stack in moved where redress(teammate, after: stack.item) {
            break
        }
        return .tookAll(moved)
    }

    /// How many copies of each item the follower's default outfit gives it.
    public func teammateOutfit(of teammate: InventoryHolder) -> [FormID: Int32] {
        let outfit = coordinator.runtime?.inventory.baseline(of: teammate).equipped ?? []
        return outfit.reduce(into: [:]) { counts, item in counts[item, default: 0] += 1 }
    }

    /// The gear routine after `item` moved between the player and `teammate`. Armour or a
    /// weapon makes the follower take off what it wears, put its outfit back on, then wear
    /// the best armour per slot and its best weapon. False when nothing ran.
    @discardableResult
    public func redress(_ teammate: InventoryHolder, after item: FormID) -> Bool {
        guard
            let equipment = coordinator.equipment,
            let family = equipment.inventory.baselines.items.definition(item)?.family,
            family == .armor || family == .weapon
        else { return false }
        let inventory = equipment.inventory
        let outfit = inventory.inventory(of: teammate).outfit.flatMap {
            inventory.baselines.outfitStacks($0, roll: inventory.roll(of: teammate))?.map(\.item)
        } ?? inventory.baseline(of: teammate).equipped
        for piece in outfit where inventory.count(of: piece, in: teammate) == 0 {
            _ = attempt { try inventory.add(piece, count: 1, to: teammate) }
        }
        let held = inventory.inventory(of: teammate).stacks.map(\.item)
        let catalog = inventory.baselines.equipment
        let armour = catalog.teammateArmour(held)
        let wear = armour + catalog.weaponPicks(worn: armour, held: held)
        _ = equipment.unequipAll(on: teammate)
        for piece in wear {
            _ = attempt { try equipment.equip(piece, on: teammate) }
        }
        return true
    }

    private func outfitCount(of item: FormID, on teammate: InventoryHolder) -> Int32 {
        teammateOutfit(of: teammate)[item] ?? 0
    }
}
