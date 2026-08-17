// World > Inventory & Equipment readout text (issue #180): the device-free
// half of the M12 verification surface.
//
// Every line the three sections show is a pure function of one
// `InventoryEquipmentSnapshot`, exactly as `ScriptsReadout` is a pure function
// of one `ScriptsSnapshot`. Keeping the wording here rather than inside the
// section view controllers is what lets the text be asserted without AppKit,
// without a Metal device, and without a game install.
//
// No AppKit import on purpose: the file compiles into both the app and the CLI
// target, so it needs no project-membership exception.

import Foundation

nonisolated enum InventoryEquipmentReadout {
    /// Longest inventory listing any of these readouts prints. A full player
    /// inventory is hundreds of stacks and this is a 2 Hz readout, not a menu.
    static let listedStackLimit = 6

    /// What the player and the open container hold, which is the accounting a
    /// grant moves. Both sides are shown together because a grant to one is
    /// only meaningful against the other.
    static func grantsText(for snapshot: InventoryEquipmentSnapshot) -> String {
        guard snapshot.isAvailable else {
            return InventoryEquipmentSnapshot.unavailable.lastActionText
        }
        let weight = String(format: "%.1f", snapshot.playerWeight)
        return [
            "Player: \(snapshot.playerStacks.count) stacks · weight \(weight) "
                + "· gold \(snapshot.playerGold)",
            stackLines(snapshot.playerStacks),
            containerHeading(snapshot),
            snapshot.hasOpenContainer ? stackLines(snapshot.containerStacks) : nil,
            snapshot.lastActionText
        ].compactMap(\.self).joined(separator: "\n")
    }

    private static func containerHeading(_ snapshot: InventoryEquipmentSnapshot) -> String {
        guard let name = snapshot.openContainerName, snapshot.hasOpenContainer else {
            return "Container: none open. Search one under "
                + "World > HUD & Interaction > Items."
        }
        return "Container: \(name) · gold \(snapshot.containerGold)"
    }

    /// Who owns the crosshair target. An unowned reference and no target at all
    /// read as two different stated conditions, never as a blank, because
    /// "nothing is highlighted" and "this belongs to nobody" are different
    /// answers to the theft question.
    static func ownershipText(for snapshot: InventoryEquipmentSnapshot) -> String {
        guard snapshot.isAvailable else {
            return InventoryEquipmentSnapshot.unavailable.lastActionText
        }
        guard let ownership = snapshot.targetOwnership else {
            return "Target: none\nPoint the walk-mode crosshair at a reference."
        }
        guard let owner = ownership.owner else {
            return """
            Target: \(ownership.name) · \(ownership.reference)
            Owner: none — taking this is not theft.
            """
        }
        let rank = ownership.factionRank.map { "\nFaction rank required: \($0)" } ?? ""
        return """
        Target: \(ownership.name) · \(ownership.reference)
        Owner: \(owner) — taking this is theft.\(rank)
        Ownership is decoded and reported only; no crime system enforces it yet.
        """
    }

    /// What the inspected owner wears, and what its appearance resolution left
    /// out. The skips are the point of the section: a piece that occupies a
    /// slot but drew nothing is otherwise indistinguishable from an equip that
    /// silently failed.
    static func equipmentText(for snapshot: InventoryEquipmentSnapshot) -> String {
        guard snapshot.isAvailable else {
            return InventoryEquipmentSnapshot.unavailable.lastActionText
        }
        let inspection = snapshot.equipInspection
        guard let name = inspection.name else {
            return "Inspecting: \(label(snapshot.equipTarget))\n"
                + "Nothing resolves that owner right now."
        }
        return [
            "Inspecting: \(label(snapshot.equipTarget)) · \(name)",
            "Appearance source: "
                + (inspection.usesRuntimeEquipment ? "runtime equipped set" : "plugin outfit"),
            equippedLines(inspection.equipped),
            skipLines(inspection.appearanceSkips)
        ].joined(separator: "\n")
    }

    static func label(_ target: EquipmentTargetSelector) -> String {
        switch target {
        case .player: "Player"
        case .nearestActor: "Nearest NPC"
        }
    }

    // MARK: - Lines

    /// One indented line per stack, truncated with a stated remainder so the
    /// readout never silently shows part of an inventory as the whole of it.
    private static func stackLines(_ stacks: [ItemStackReadout]) -> String {
        guard !stacks.isEmpty else { return "  empty" }
        var lines = stacks.prefix(listedStackLimit).map { "  \($0.count) × \($0.name)" }
        if stacks.count > listedStackLimit {
            lines.append("  … \(stacks.count - listedStackLimit) more")
        }
        return lines.joined(separator: "\n")
    }

    private static func equippedLines(_ items: [EquippedItemReadout]) -> String {
        guard !items.isEmpty else { return "Wearing: nothing" }
        var lines = ["Wearing:"]
        // The enchantment and its remaining charge trail the slots where the
        // piece has one (issue #472), so a hit that drained a weapon is readable
        // here rather than only through a health bar.
        lines += items.prefix(listedStackLimit).map { item in
            let enchantment = item.enchantment.map { " · \($0)" } ?? ""
            return "  \(item.name) · \(item.occupancy)\(enchantment)"
        }
        if items.count > listedStackLimit {
            lines.append("  … \(items.count - listedStackLimit) more")
        }
        return lines.joined(separator: "\n")
    }

    private static func skipLines(_ skips: [String]) -> String {
        guard !skips.isEmpty else { return "Appearance skips: none" }
        return (["Appearance skips:"] + skips.prefix(listedStackLimit).map { "  \($0)" }
            + (skips.count > listedStackLimit
                ? ["  … \(skips.count - listedStackLimit) more"]
                : []))
            .joined(separator: "\n")
    }
}
