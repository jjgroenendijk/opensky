// VRST chunk: the hour each merchant chest was last stocked comes back after a save,
// so a chest still restocks on time after a load.

import Foundation
import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyInventoryInterface
@testable import OpenSkySave
import OpenSkySaveFixtures
@testable import OpenSkyWorldState
import Testing

@MainActor
struct VendorRestockSaveTests {
    private let ledger = VendorRestockLedger(stockedAt: [
        .plugin(name: "Skyrim.esm", objectID: 0x0009_8B0D): 1340.25,
        .plugin(name: "Skyrim.esm", objectID: 0x0001_A6E3): 1290
    ])

    private func snapshot(_ ledger: VendorRestockLedger) -> WorldStateSnapshot {
        OpenSkySaveFixture.snapshot(
            [OpenSkySaveFixture.entry(key: .player, cell: nil, components: [ledger.erased])],
            bystanderCell: OpenSkySaveFixture.riverwood
        )
    }

    @Test func stockingHoursSurviveAnEncodeAndDecode() throws {
        let data = OpenSkySaveFixture.encode(snapshot(ledger))
        #expect(data.range(of: Data("VRST".utf8)) != nil)
        let file = try OpenSkySaveDecoder.decode(data)
        let store = WorldStateStore()
        store.restore(from: file.snapshot)
        #expect(store.component(VendorRestockLedger.self, for: .player) == ledger)
    }

    @Test func theSameHoursWriteTheSameBytes() {
        let reordered = VendorRestockLedger(stockedAt: Dictionary(
            uniqueKeysWithValues: ledger.stockedAt.reversed()
        ))
        #expect(
            OpenSkySaveFixture.encode(snapshot(ledger))
                == OpenSkySaveFixture.encode(snapshot(reordered))
        )
    }

    @Test func aCountLargerThanThePayloadThrows() {
        var writer = BinaryWriter()
        writer.writeUInt32(1000)
        #expect(throws: (any Error).self) {
            try OpenSkySaveVendorRestockDecoder.decode(writer.data)
        }
    }
}
