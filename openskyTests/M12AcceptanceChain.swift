// The M12 gate's world, built once and shared by the loop and render halves
// (issue #180).
//
// One synthetic plugin — `InventoryBaselineFixture`, which the rest of M12
// already tests against — plus three placed references: a loose iron sword to
// take, a chest to transfer through, and a second chest standing in as the
// merchant. A guard actor is the owner an equip is visible on.
//
// No game content anywhere: every record is assembled in code from the
// published layouts (AGENTS.md "Legal & IP boundary"), and nothing here needs a
// Metal device or an install.

import Foundation
@testable import opensky
import simd

/// The engine objects the gate drives, wired the way `wireWorldItems` wires
/// them: one store, one inventory runtime over the fixture baselines, one world
/// item runtime over a fixture reference index, and one equipment runtime.
@MainActor
struct M12AcceptanceChain {
    typealias Fixture = InventoryBaselineFixture

    /// The cell every reference in the fixture lives in, so a mutation's
    /// attribution can be asserted against one known location.
    static let cell = CellSceneLocation.exterior(CellCoordinate(x: 2, y: -1))

    /// Placed references. Distinct from the base FormIDs above them: a
    /// reference is not its record, and the gate asserts on both.
    static let looseSwordReference = FormID(0x0000_5000)
    static let chestReference = FormID(0x0000_5010)
    static let merchantReference = FormID(0x0000_5020)
    static let guardReference = FormID(0x0000_5030)
    /// The NPC_ that owns the loose sword and the merchant chest, which is what
    /// makes taking either of them theft in the data.
    static let ownerActor = Fixture.guardActor

    let store = WorldStateStore()
    let references: PapyrusWorldFixtureReferences
    let runtime: WorldItemRuntime
    let equipment: EquipmentRuntime
    let pricing = BarterPricing.vanilla

    init() throws {
        let baselines = try Fixture.resolver()
        let inventory = InventoryRuntime(store: store, baselines: baselines)
        references = try PapyrusWorldFixtureReferences(
            entries: Self.entries(), cell: Self.cell
        )
        runtime = WorldItemRuntime(inventory: inventory, references: references)
        equipment = try EquipmentRuntime(
            inventory: inventory,
            catalog: EquipmentCatalog.build(from: ESMFile(data: Fixture.pluginBytes()))
        )
    }

    // MARK: - Holders

    var player: InventoryHolder {
        runtime.player
    }

    var chest: InventoryHolder {
        InventoryHolder(
            key: Self.key(Self.chestReference), owner: .container(base: Fixture.chest),
            cell: Self.cell
        )
    }

    var merchant: InventoryHolder {
        InventoryHolder(
            key: Self.key(Self.merchantReference),
            owner: .container(base: Fixture.emptyChest),
            cell: Self.cell
        )
    }

    var guardActor: InventoryHolder {
        InventoryHolder(
            key: Self.key(Self.guardReference), owner: .actor(base: Fixture.guardActor),
            cell: Self.cell
        )
    }

    var barter: BarterSession {
        BarterSession(runtime: runtime, merchant: merchant, pricing: pricing)
    }

    // MARK: - Interactions

    static func take(_ reference: FormID, base: FormID) -> PlacedInteraction {
        interaction(reference: reference, base: base, action: .take)
    }

    static func search(_ reference: FormID, base: FormID) -> PlacedInteraction {
        interaction(reference: reference, base: base, action: .search)
    }

    static func interaction(
        reference: FormID,
        base: FormID,
        action: InteractionAction
    ) -> PlacedInteraction {
        PlacedInteraction(
            reference: reference,
            base: base,
            position: .zero,
            name: "M12 \(reference)",
            action: action,
            actionLabel: action.defaultLabel,
            sounds: nil
        )
    }

    static func key(_ reference: FormID) -> ReferenceKey {
        .plugin(name: "skyrim.esm", objectID: reference.objectID)
    }

    // MARK: - Fixture references

    private static func entries() throws -> [RuntimeReferenceEntry] {
        try [
            entry(looseSwordReference, base: Fixture.sword, owner: ownerActor, rank: 2),
            entry(chestReference, base: Fixture.chest),
            entry(merchantReference, base: Fixture.emptyChest, owner: ownerActor),
            entry(guardReference, base: Fixture.guardActor)
        ]
    }

    /// One placed reference, decoded from real REFR bytes rather than
    /// synthesized, because `XOWN` and `XRNK` are the fields the gate's
    /// ownership readout reads and only the decoder produces them.
    private static func entry(
        _ formID: FormID,
        base: FormID,
        owner: FormID? = nil,
        rank: Int32? = nil
    ) throws -> RuntimeReferenceEntry {
        var fields = InventoryFixture.formIDField("NAME", base.rawValue)
        fields += ESMFixture.field("DATA", Data(count: 24))
        if let owner {
            fields += InventoryFixture.formIDField("XOWN", owner.rawValue)
        }
        if let rank {
            var value = Data()
            value.appendUInt32(UInt32(bitPattern: rank))
            fields += ESMFixture.field("XRNK", value)
        }
        let record = try InventoryFixture.record(
            ESMFixture.record("REFR", formID: formID.rawValue, data: fields)
        )
        return try RuntimeReferenceEntry(
            key: key(formID),
            formID: formID,
            isPersistent: false,
            record: .reference(PlacedReference(record: record))
        )
    }
}
