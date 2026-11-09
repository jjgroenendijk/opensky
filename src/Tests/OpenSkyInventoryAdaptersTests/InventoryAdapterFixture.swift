// Placed records and interactions the Inventory adapter tests hand to the fakes.

import Foundation
import OpenSkyFormatsESM
import OpenSkyFormatsTesting
import OpenSkyGameData
import OpenSkyWorldInterface
import OpenSkyWorldState
import OpenSkyWorldTesting

enum InventoryAdapterFixture {
    static let referenceID: UInt32 = 0x10
    static let baseID: UInt32 = 0x20

    static var key: ReferenceKey {
        PackageRuntimeFixture.key(referenceID)
    }

    static func actorEntry() throws -> RuntimeReferenceEntry {
        try PackageRuntimeFixture.residentActor(referenceID, base: baseID)
    }

    static func referenceEntry() throws -> RuntimeReferenceEntry {
        let fields = PackageRuntimeFixture.formIDField("NAME", baseID)
            + ESMFixture.field("DATA", Data(count: 24))
        let record = try PlacedReference(record: ESMFixture.parseRecord(
            ESMFixture.record("REFR", formID: referenceID, data: fields)
        ))
        return RuntimeReferenceEntry(
            key: key, formID: FormID(referenceID), isPersistent: false, record: .reference(record)
        )
    }

    static func interaction(
        _ action: InteractionAction,
        lock: LockData? = nil,
        seats: [FurnitureSeat] = []
    ) -> PlacedInteraction {
        var interaction = PlacedInteraction(
            reference: FormID(referenceID), base: FormID(baseID), position: SIMD3(1, 2, 3),
            name: "Thing", action: action, actionLabel: action.defaultLabel, sounds: nil, lock: lock
        )
        interaction.seats = seats
        return interaction
    }

    static func target(_ interaction: PlacedInteraction) -> InteractionTarget {
        InteractionTarget(interaction: interaction, hitPosition: .zero, distance: 64)
    }

    static func seat() -> FurnitureSeat {
        FurnitureSeat(
            position: .zero, heading: 0, animationType: FurnitureSeat.sitAnimation, keyword: nil
        )
    }
}
