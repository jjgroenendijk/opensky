// The TMPR save chunk: tempered copies survive a round trip, and no quality writes
// no chunk.

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

    private func encode(_ state: TemperedItemState) -> Data {
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
        let state = TemperedItemState(levels: [sword.rawValue: [1, 4]])
        let file = try OpenSkySaveDecoder.decode(encode(state))
        let restored = file.snapshot.entries.first { $0.key == owner }?
            .delta.component(TemperedItemState.self)
        #expect(restored == state)
        #expect(restored?.copies(of: sword, held: 3) == [4, 1, 0])
    }

    @Test func noQualityWritesNoChunk() {
        #expect(!encode(TemperedItemState()).contains(Data("TMPR".utf8)))
        #expect(encode(TemperedItemState(levels: [sword.rawValue: [2]]))
            .contains(Data("TMPR".utf8)))
    }
}
