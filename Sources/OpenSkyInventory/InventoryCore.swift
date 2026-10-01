// The inventory decisions as pure functions: item names, slot listings,
// grant checks and outcome sentences. `InventoryCoordinator` is the shell
// that reads the world. See docs/engine/coordinators.md.

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface

/// Pure inventory rules. Values in, values out.
nonisolated public enum InventoryCore {
    public static let noRuntimeText = "World items unavailable: no game data loaded."
    public static let noEquipmentText = "Equipment unavailable: no game data loaded."
    public static let noContainerText = "No container open."

    /// FULL name, else editor ID, else the FormID. Never empty, so a readout
    /// line always names something.
    public static func displayName(of item: FormID, definition: ItemDefinition?) -> String {
        guard let definition else { return item.description }
        if case let .inline(value) = definition.name, !value.isEmpty {
            return value
        }
        return definition.editorID ?? item.description
    }

    /// The reference key plus the NPC_ base, which is what the record dump
    /// takes as input.
    public static func actorName(_ holder: InventoryHolder) -> String {
        guard case let .actor(base) = holder.owner else { return holder.key.description }
        return "\(holder.key.description) (base \(base))"
    }

    public static func noTargetText(_ target: EquipmentTargetSelector) -> String {
        switch target {
        case .player: "No player inventory."
        case .nearestActor: "No resident actor to equip on."
        }
    }

    /// The first held stack that occupies a slot and is not worn yet. Stacks
    /// are in FormID order, so the answer is stable.
    public static func firstEquippable(
        in state: ReferenceInventoryState,
        occupancy: (FormID) -> EquipmentOccupancy
    ) -> FormID? {
        state.stacks.first {
            !occupancy($0.item).isEmpty && !state.isEquipped($0.item)
        }?.item
    }

    /// "body|forearms" plus hands, so a conflict reads off the panel without
    /// decoding a bitfield.
    public static func describe(_ occupancy: EquipmentOccupancy) -> String {
        let namedSlots = BodySlots.namedSlots.filter { occupancy.slots.contains($0.slots) }
        var parts = namedSlots.map(\.name)
        if occupancy.hands.contains(.rightHand) {
            parts.append("right hand")
        }
        if occupancy.hands.contains(.leftHand) {
            parts.append("left hand")
        }
        // A slot with no name, such as 44, still conflicts, so it shows.
        let named = namedSlots.reduce(into: BodySlots()) { $0.formUnion($1.slots) }
        let rest = occupancy.slots.subtracting(named)
        if !rest.isEmpty {
            parts.append("raw 0x" + String(rest.rawValue, radix: 16))
        }
        return parts.isEmpty ? "no slots" : parts.joined(separator: "|")
    }

    /// Why a grant is refused, or nil when it may go ahead.
    public static func grantRefusal(item: FormID, count: Int32, isKnown: Bool) -> String? {
        guard count > 0 else {
            return "Grant refused: a count of \(count) is not a stack."
        }
        guard isKnown else {
            return "Grant refused: no loaded plugin describes \(item), so it has no "
                + "weight, value or name."
        }
        return nil
    }

    public static func equipSentence(
        changed: Bool,
        item: String,
        target: String,
        unequipped: [String]
    ) -> String {
        guard changed else { return "\(item) was already equipped on \(target)." }
        let displaced = unequipped.isEmpty
            ? ""
            : ", unequipped " + unequipped.joined(separator: ", ")
        return "Equipped \(item) on \(target)\(displaced)."
    }

    public static func takeAllSentence(_ moved: [InventoryStack]) -> String {
        let total = moved.reduce(0) { $0 + Int($1.count) }
        return "Took all: \(total) items in \(moved.count) stacks."
    }

    public static func takeSentence(item: String, bounty: Int32) -> String {
        bounty > 0 ? "Stole \(item) — \(bounty) bounty." : "Took \(item)."
    }
}
