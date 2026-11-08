// The TMPR and ICPY save chunks: item copies survive a round trip, and plain copies
// write no chunk.

import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyInventoryInterface
@testable import OpenSkySave
import OpenSkySaveFixtures
@testable import OpenSkyWorldState
import Testing

struct TemperedItemSaveTests {
    private let owner = ReferenceKey.player
    private let sword = FormID(0x0001_2EB7)

    private func encode(_ state: ItemCopyState) -> Data {
        let snapshot = WorldStateSnapshot(
            entries: [
                OpenSkySaveFixture.entry(key: owner, cell: nil, components: [state.erased])
            ],
            nextGeneratedSequence: 1,
            sequence: 1
        )
        return OpenSkySaveEncoder.encode(
            snapshot: snapshot,
            fingerprint: OpenSkySaveFixture.fingerprint,
            metadata: OpenSkySaveFixture.metadata
        )
    }

    @Test func temperedCopiesSurviveARoundTrip() throws {
        let state = ItemCopyState(levels: [sword.rawValue: [1, 4]])
        let file = try OpenSkySaveDecoder.decode(encode(state))
        let restored = file.snapshot.entries.first { $0.key == owner }?
            .delta.component(ItemCopyState.self)
        #expect(restored == state)
        #expect(restored?.levels(of: sword, held: 3) == [4, 1, 0])
    }

    /// A soul, a spent charge, and a made enchantment ride in `ICPY`, which replaces the
    /// level-only `TMPR` state on load.
    @Test func everyCopyFieldSurvivesARoundTrip() throws {
        let gem = FormID(0x0002_E4E2)
        let state = ItemCopyState(copies: [
            sword.rawValue: [
                ItemCopy(level: 2, charge: 120, enchantment: FormID(0xFF00_0001)),
                ItemCopy(level: 1)
            ],
            gem.rawValue: [ItemCopy(soul: 1)]
        ])
        let file = try OpenSkySaveDecoder.decode(encode(state))
        let restored = file.snapshot.entries.first { $0.key == owner }?
            .delta.component(ItemCopyState.self)
        #expect(restored == state)
        #expect(restored?.copies(of: gem, held: 2) == [ItemCopy(soul: 1), .plain])
        #expect(encode(state).contains(Data("ICPY".utf8)))
        #expect(!encode(ItemCopyState(levels: [sword.rawValue: [2]])).contains(Data("ICPY".utf8)))
    }

    @Test func noQualityWritesNoChunk() {
        #expect(!encode(ItemCopyState()).contains(Data("TMPR".utf8)))
        #expect(encode(ItemCopyState(levels: [sword.rawValue: [2]]))
            .contains(Data("TMPR".utf8)))
    }
}
