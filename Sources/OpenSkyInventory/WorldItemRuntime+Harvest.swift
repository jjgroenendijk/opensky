// Harvesting a FLOR or TREE reference: grant its produce and set the harvested
// component with the game day. One produce item per harvest; the seasonal chance
// does not apply yet. `HarvestRegrowth` decides when it grows back.
// See docs/engine/interaction.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyWorldInterface
import OpenSkyWorldState

/// Why a harvest wrote nothing.
nonisolated public enum HarvestError: Error, Equatable {
    case notHarvestable(FormID)
    case unknownReference(FormID)
    case alreadyHarvested(FormID)
    /// The base has no `PFIG`, or it names nothing the item index knows.
    case noProduce(FormID)
}

/// What one successful harvest granted.
nonisolated public struct HarvestOutcome: Equatable, Sendable {
    public let reference: ReferenceKey
    /// The stacks that entered the inventory: the produce, or its leveled pick.
    public let granted: [InventoryStack]
}

extension WorldItemRuntime {
    /// The stored harvest of the reference behind `interaction`. Nil for a
    /// reference no resident cell knows, or one never harvested.
    public func harvestState(of interaction: PlacedInteraction) -> ReferenceHarvestState? {
        guard let entry = references?.referenceEntry(formID: interaction.reference) else {
            return nil
        }
        return store.component(ReferenceHarvestState.self, for: entry.key)
    }

    /// Whether the plant behind `interaction` reads as harvested on game day `day`.
    public func isHarvested(_ interaction: PlacedInteraction, onDay day: Float?) -> Bool {
        harvestRegrowth.isHarvested(harvestState(of: interaction), onDay: day)
    }

    /// The game day the plant behind `interaction` grows back on, or nil.
    public func regrowthDay(of interaction: PlacedInteraction) -> Float? {
        harvestRegrowth.regrowthDay(of: harvestState(of: interaction))
    }

    /// `interaction` with the harvested label when its plant reads as harvested.
    public func labelled(_ interaction: PlacedInteraction, onDay day: Float?) -> PlacedInteraction {
        guard interaction.action == .harvest, isHarvested(interaction, onDay: day) else {
            return interaction
        }
        return interaction.relabelled(InteractionAction.harvestedLabel)
    }

    /// Grants the produce of the plant behind `interaction` and marks it harvested
    /// on game day `day`. A plant that grew back can be harvested again.
    /// - Throws: `HarvestError`, or `InventoryError.countOverflow`. Nothing is written then.
    @discardableResult
    public func harvest(
        _ interaction: PlacedInteraction,
        onDay day: Float?
    ) throws -> HarvestOutcome {
        guard interaction.action == .harvest else {
            throw HarvestError.notHarvestable(interaction.reference)
        }
        guard let entry = references?.referenceEntry(formID: interaction.reference) else {
            throw HarvestError.unknownReference(interaction.reference)
        }
        if isHarvested(interaction, onDay: day) {
            throw HarvestError.alreadyHarvested(interaction.reference)
        }
        let baselines = inventory.baselines
        let granted = interaction.produce?.ingredient.map {
            baselines.expanded($0, count: 1).filter { baselines.items.definition($0.item) != nil }
        } ?? []
        guard !granted.isEmpty else { throw HarvestError.noProduce(interaction.base) }
        try inventory.apply(removing: [], adding: granted, on: player)
        store.set(
            ReferenceHarvestState(isHarvested: true, harvestedOnDay: day),
            for: entry.key,
            in: references?.cellLocation(of: entry.key)
        )
        return HarvestOutcome(reference: entry.key, granted: granted)
    }

    /// Clears the harvested component: the plant grows back now.
    public func resetHarvest(_ interaction: PlacedInteraction) throws {
        guard let entry = references?.referenceEntry(formID: interaction.reference) else {
            throw HarvestError.unknownReference(interaction.reference)
        }
        store.reset(ReferenceHarvestState.componentKind, for: entry.key)
    }
}
