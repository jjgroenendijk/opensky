// Harvesting a FLOR or TREE reference: roll its `PFPC` chance for the season, grant
// the produce on a yield, and set the harvested component. A failed roll still
// harvests the plant. It grows back when its cell resets (`WorldItemRuntime+CellReset`).
// See docs/engine/interaction.md.

import Foundation
import OpenSkyFormatsCore
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
    /// Empty when the season's roll failed.
    public let granted: [InventoryStack]
}

/// The season and day one harvest happens in.
nonisolated public struct HarvestMoment: Equatable, Sendable {
    /// Game days passed. Nil without a clock.
    public let day: Float?
    /// Nil without a clock; the season's chance then does not apply.
    public let season: HarvestSeason?

    public init(day: Float?, season: HarvestSeason?) {
        self.day = day
        self.season = season
    }
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

    /// Whether the plant behind `interaction` reads as harvested. It stays so until
    /// its cell resets.
    public func isHarvested(_ interaction: PlacedInteraction) -> Bool {
        harvestState(of: interaction)?.isHarvested ?? false
    }

    /// `interaction` with the harvested label when its plant reads as harvested.
    public func labelled(_ interaction: PlacedInteraction) -> PlacedInteraction {
        guard interaction.action == .harvest, isHarvested(interaction) else {
            return interaction
        }
        return interaction.relabelled(InteractionAction.harvestedLabel)
    }

    /// Rolls the season's chance, grants the produce `count` times over on a yield,
    /// and marks the plant harvested.
    /// - Throws: `HarvestError`, or `InventoryError.countOverflow`. Nothing is written then.
    @discardableResult
    public func harvest(
        _ interaction: PlacedInteraction,
        at moment: HarvestMoment,
        count: Int32 = 1
    ) throws -> HarvestOutcome {
        guard interaction.action == .harvest else {
            throw HarvestError.notHarvestable(interaction.reference)
        }
        guard let entry = references?.referenceEntry(formID: interaction.reference) else {
            throw HarvestError.unknownReference(interaction.reference)
        }
        if isHarvested(interaction) {
            throw HarvestError.alreadyHarvested(interaction.reference)
        }
        let baselines = inventory.baselines
        let produce = interaction.produce?.ingredient.map {
            baselines.expanded($0, count: max(1, count))
                .filter { baselines.items.definition($0.item) != nil }
        } ?? []
        guard !produce.isEmpty else { throw HarvestError.noProduce(interaction.base) }
        let yields = HarvestSeason.yields(
            chances: interaction.produce?.seasonalChance,
            season: moment.season,
            roll: Self.harvestRoll(entry.key, day: moment.day)
        )
        let granted = yields ? produce : []
        try inventory.apply(removing: [], adding: granted, on: player)
        store.set(
            ReferenceHarvestState(isHarvested: true, harvestedOnDay: moment.day),
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

    /// A number in [0, 100) from the plant and the day, so a harvest replays exactly.
    static func harvestRoll(_ key: ReferenceKey, day: Float?) -> Float {
        let dayBits = UInt64((day ?? 0).bitPattern)
        var seed: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in key.description.utf8 {
            seed = (seed ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
        }
        var generator = SplitMix64(seed: seed ^ dayBits)
        return Float.random(in: 0 ..< 100, using: &generator)
    }
}
