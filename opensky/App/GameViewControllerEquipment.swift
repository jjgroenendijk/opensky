// World > HUD & Interaction > Items, equipment half (issue #178, roadmap item
// 12.2.1). Satellite of GameViewControllerItems.swift, split for file-length
// limits and because equipping is a distinct concern from take/drop/containers.
//
// Two targets, and the split matters. Equipping on the player exercises the
// state path — the equipped set, the conflict resolution, the journal entry —
// and changes nothing on screen, because the player has no rendered body until
// M14. Equipping on the nearest resident NPC is the *visual* proof: the write
// is attributed to that actor's cell, `CellStreamer.noteStateMutation` queues a
// rebuild, and the rebuilt actor resolves its appearance from the equipped set
// instead of its plugin default outfit.
//
// Everything degrades to a stated non-answer rather than a crash, matching the
// take/drop half: no game data means no catalog, which the panel reports as
// unavailable instead of silently doing nothing.

import AppKit

extension GameViewController {
    /// Equips on the selected target, unequipping whatever conflicts.
    @discardableResult
    func equipItem(_ item: FormID?, on target: EquipmentTargetSelector) -> String {
        guard let equipment = worldItems.equipment else { return Self.noEquipmentText }
        guard let holder = holder(for: target) else {
            worldItems.lastActionText = Self.noTargetText(target)
            return worldItems.lastActionText
        }
        guard let chosen = item ?? firstEquippableItem(on: holder, equipment: equipment) else {
            worldItems.lastActionText = "Nothing equippable held."
            return worldItems.lastActionText
        }
        do {
            let change = try equipment.equip(chosen, on: holder)
            // After the write, so the reconcile reads the equipped set this equip
            // produced (issue #472). Every equip path in this controller ends with
            // this call; see `WornEnchantmentApplication` for why it reconciles
            // rather than applying just the item that moved.
            refreshWornEnchantments(on: holder)
            let displaced = change.unequipped.isEmpty
                ? ""
                : ", unequipped " + change.unequipped.map { name(of: $0) }
                .joined(separator: ", ")
            worldItems.lastActionText = change.changed
                ? "Equipped \(name(of: chosen)) on \(label(target))\(displaced)."
                : "\(name(of: chosen)) was already equipped on \(label(target))."
        } catch {
            worldItems.lastActionText = "Equip failed: \(String(describing: error))"
        }
        return worldItems.lastActionText
    }

    /// Unequips on the selected target.
    @discardableResult
    func unequipItem(_ item: FormID?, on target: EquipmentTargetSelector) -> String {
        guard let equipment = worldItems.equipment else { return Self.noEquipmentText }
        guard let holder = holder(for: target) else {
            worldItems.lastActionText = Self.noTargetText(target)
            return worldItems.lastActionText
        }
        guard let chosen = item ?? equipment.equipped(on: holder).first else {
            worldItems.lastActionText = "\(label(target)) is wearing nothing."
            return worldItems.lastActionText
        }
        let changed = equipment.unequip(chosen, on: holder)
        refreshWornEnchantments(on: holder)
        worldItems.lastActionText = changed
            ? "Unequipped \(name(of: chosen)) on \(label(target))."
            : "\(name(of: chosen)) was not equipped on \(label(target))."
        return worldItems.lastActionText
    }

    /// What one target is wearing, for the readout. Empty when equipment is
    /// unavailable or nothing resolves the target.
    func equippedReadout(on target: EquipmentTargetSelector) -> [EquippedItemReadout] {
        guard let equipment = worldItems.equipment, let holder = holder(for: target) else {
            return []
        }
        let values = actorValueHolder(for: holder.key)
        return equipment.equipped(on: holder).map { item in
            EquippedItemReadout(
                item: item,
                name: name(of: item),
                occupancy: Self.describe(equipment.occupancy(of: item)),
                enchantment: enchantmentLine(of: item, on: values)
            )
        }
    }

    /// The nearest resident ACHR as an inventory holder, or nil when none is
    /// loaded. Also what the readout names, so the panel and the action always
    /// agree on which actor "nearest" means.
    func nearestActorHolder() -> InventoryHolder? {
        guard
            let runtime = worldItems.runtime,
            let streamer,
            let renderer,
            let entry = streamer.nearestActorEntry(to: renderer.freeFlyCamera.position),
            let actor = entry.placedActor
        else { return nil }
        return runtime.actorHolder(entry: entry, base: actor.base)
    }

    /// An actor holder's display name: its NPC_ base FormID, which is what the
    /// user types into the record dump to see what it resolved to.
    func name(ofActor holder: InventoryHolder) -> String {
        guard case let .actor(base) = holder.owner else { return holder.key.description }
        return "\(holder.key.description) (base \(base))"
    }

    // MARK: - Private

    private static let noEquipmentText =
        "Equipment unavailable: no game data loaded."

    private static func noTargetText(_ target: EquipmentTargetSelector) -> String {
        switch target {
        case .player: "No player inventory."
        case .nearestActor: "No resident actor to equip on."
        }
    }

    private func holder(for target: EquipmentTargetSelector) -> InventoryHolder? {
        switch target {
        case .player: worldItems.runtime?.player
        case .nearestActor: nearestActorHolder()
        }
    }

    private func label(_ target: EquipmentTargetSelector) -> String {
        switch target {
        case .player: "the player"
        case .nearestActor: nearestActorHolder().map { name(ofActor: $0) } ?? "no actor"
        }
    }

    /// The first held stack the catalog describes as equippable and that is not
    /// already worn — what the blank-FormID control acts on. Stacks are in
    /// FormID order, so this is deterministic.
    private func firstEquippableItem(
        on holder: InventoryHolder,
        equipment: EquipmentRuntime
    ) -> FormID? {
        let state = equipment.inventory.inventory(of: holder)
        return state.stacks.first {
            !equipment.occupancy(of: $0.item).isEmpty && !state.isEquipped($0.item)
        }?.item
    }

    /// "body|forearms" style slot listing plus hands — enough to read a
    /// conflict off the panel without decoding a bitfield by hand.
    private static func describe(_ occupancy: EquipmentOccupancy) -> String {
        var parts = BodySlots.namedSlots
            .filter { occupancy.slots.contains($0.slots) }
            .map(\.name)
        if occupancy.hands.contains(.rightHand) {
            parts.append("right hand")
        }
        if occupancy.hands.contains(.leftHand) {
            parts.append("left hand")
        }
        // Unnamed biped slots still have to show, or a mod-authored slot 50
        // piece reads as occupying nothing while conflicting with things.
        let named = BodySlots.namedSlots
            .filter { occupancy.slots.contains($0.slots) }
            .reduce(into: BodySlots()) { $0.formUnion($1.slots) }
        let rest = occupancy.slots.subtracting(named)
        if !rest.isEmpty {
            parts.append("raw 0x" + String(rest.rawValue, radix: 16))
        }
        return parts.isEmpty ? "no slots" : parts.joined(separator: "|")
    }
}
