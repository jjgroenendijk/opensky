// Harvesting a FLOR or TREE reference: grant its produce and set the harvested
// component. One produce item per harvest; the seasonal chance does not apply yet.
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
    /// Whether the reference behind `interaction` was harvested. False for a
    /// reference no resident cell knows.
    public func isHarvested(_ interaction: PlacedInteraction) -> Bool {
        guard let entry = references?.referenceEntry(formID: interaction.reference) else {
            return false
        }
        return store.component(ReferenceHarvestState.self, for: entry.key)?.isHarvested ?? false
    }

    /// `interaction` with the harvested label when its plant was harvested.
    public func labelled(_ interaction: PlacedInteraction) -> PlacedInteraction {
        guard interaction.action == .harvest, isHarvested(interaction) else { return interaction }
        return interaction.relabelled(InteractionAction.harvestedLabel)
    }

    /// Grants the produce of the plant behind `interaction` and marks it harvested.
    /// - Throws: `HarvestError`, or `InventoryError.countOverflow`. Nothing is written then.
    @discardableResult
    public func harvest(_ interaction: PlacedInteraction) throws -> HarvestOutcome {
        guard interaction.action == .harvest else {
            throw HarvestError.notHarvestable(interaction.reference)
        }
        guard let entry = references?.referenceEntry(formID: interaction.reference) else {
            throw HarvestError.unknownReference(interaction.reference)
        }
        if store.component(ReferenceHarvestState.self, for: entry.key)?.isHarvested == true {
            throw HarvestError.alreadyHarvested(interaction.reference)
        }
        let baselines = inventory.baselines
        let granted = interaction.produce?.ingredient.map {
            baselines.expanded($0, count: 1).filter { baselines.items.definition($0.item) != nil }
        } ?? []
        guard !granted.isEmpty else { throw HarvestError.noProduce(interaction.base) }
        try inventory.apply(removing: [], adding: granted, on: player)
        store.set(
            ReferenceHarvestState.harvested,
            for: entry.key,
            in: references?.cellLocation(of: entry.key)
        )
        return HarvestOutcome(reference: entry.key, granted: granted)
    }

    /// Clears the harvested component, which is where a future cell reset regrows a plant.
    public func resetHarvest(_ interaction: PlacedInteraction) throws {
        guard let entry = references?.referenceEntry(formID: interaction.reference) else {
            throw HarvestError.unknownReference(interaction.reference)
        }
        store.reset(ReferenceHarvestState.componentKind, for: entry.key)
    }
}
