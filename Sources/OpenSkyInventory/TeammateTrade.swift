// A follower's trade: its starting outfit stays with it, and it carries no more than
// its `CarryWeight`. UESP "Skyrim:Followers". See docs/engine/barter.md#a-followers-trade.

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface

nonisolated public enum TeammateTradeText: String, GameSettingTextKey {
    case cannotTakeOutfit = "sTeammateCantTakeOutfit"
    /// Follows the follower's name.
    case overencumbered = "sTeammateOverencumbered"

    public var fallback: String {
        switch self {
        case .cannotTakeOutfit: "You can't take your teammate's starting armor."
        case .overencumbered: "can't carry any more."
        }
    }
}

/// What the rule knows about one item moving to or from a follower.
nonisolated public struct TeammateTradeFacts: Equatable, Sendable {
    /// How many of the item the follower carries now.
    public var carried: Int32 = 0
    /// How many of the item its default outfit gives it.
    public var outfit: Int32 = 0
    /// The follower's carried weight before the move.
    public var carriedWeight: Float = 0
    /// The weight the move adds to the follower.
    public var addedWeight: Float = 0
    /// The follower's `CarryWeight`. Nil without actor values, which refuses nothing.
    public var capacity: Float?

    public init() {}
}

nonisolated public enum TeammateTradeRule {
    /// The refusal of moving `count` of an item, or nil to let it through. A copy beyond
    /// the outfit's own may be taken, as UESP's note on identical armour shows.
    public static func refusal(
        _ transfer: ContainerTransfer,
        count: Int32,
        _ facts: TeammateTradeFacts
    )
        -> TeammateTradeText?
    {
        switch transfer {
        case .take:
            facts.outfit > 0 && facts.carried - count < facts.outfit ? .cannotTakeOutfit : nil
        case .store:
            facts.capacity.map { facts.carriedWeight + facts.addedWeight > $0 } == true
                ? .overencumbered : nil
        case .buy, .sell:
            nil
        }
    }
}

extension InventoryCoordinator {
    /// The refusal of moving `count` of `item` to or from the follower `teammate`.
    public func teammateRefusal(
        _ transfer: ContainerTransfer, item: FormID, count: Int32, teammate: InventoryHolder
    ) -> TeammateTradeText? {
        guard let inventory = runtime?.inventory else { return nil }
        var facts = TeammateTradeFacts()
        facts.carried = inventory.count(of: item, in: teammate)
        facts.outfit = outfitCount(of: item, on: teammate)
        facts.carriedWeight = inventory.carriedWeight(of: teammate)
        facts.addedWeight = (inventory.baselines.items.definition(item)?.weight ?? 0) * Float(count)
        facts.capacity = world.carryWeight(of: teammate.key)
        return TeammateTradeRule.refusal(transfer, count: count, facts)
    }

    /// Takes everything but the follower's starting outfit.
    public func takeAllFromTeammate(_ teammate: InventoryHolder) -> ItemActionOutcome {
        guard let runtime else { return .unavailable }
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
        reportTaken(moved, from: session)
        return .tookAll(moved)
    }

    /// How many copies of each item the follower's default outfit gives it.
    public func teammateOutfit(of teammate: InventoryHolder) -> [FormID: Int32] {
        let outfit = runtime?.inventory.baseline(of: teammate).equipped ?? []
        return outfit.reduce(into: [:]) { counts, item in counts[item, default: 0] += 1 }
    }

    private func outfitCount(of item: FormID, on teammate: InventoryHolder) -> Int32 {
        teammateOutfit(of: teammate)[item] ?? 0
    }
}
