// HRVS and HRVD chunks: harvested flora in the native save. A harvested plant
// comes back harvested with its day, and a session with no harvest writes no chunk.

import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyInventoryInterface
@testable import OpenSkySave
import OpenSkySaveFixtures
@testable import OpenSkyWorldState
import Testing

@MainActor
struct HarvestSaveTests {
    private let plant = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x0004_B9E0)

    private func snapshot() -> WorldStateSnapshot {
        OpenSkySaveFixture.snapshot(
            [
                OpenSkySaveFixture.entry(
                    key: plant,
                    cell: OpenSkySaveFixture.whiterun,
                    components: [ReferenceHarvestState.harvested.erased]
                )
            ],
            bystanderCell: OpenSkySaveFixture.riverwood
        )
    }

    @Test func aHarvestedPlantSurvivesAnEncodeAndDecode() throws {
        let original = snapshot()
        let data = OpenSkySaveFixture.encode(original)
        #expect(data.range(of: Data("HRVS".utf8)) != nil)
        let file = try OpenSkySaveDecoder.decode(data)
        #expect(file.snapshot == original)
        let delta = try #require(file.snapshot[plant])
        #expect(delta.sortedKinds == [.harvest])
        #expect(delta.cell == OpenSkySaveFixture.whiterun)

        let store = WorldStateStore()
        store.restore(from: file.snapshot)
        #expect(store.component(ReferenceHarvestState.self, for: plant) == .harvested)
    }

    @Test func noHarvestWritesNoChunk() {
        let data = OpenSkySaveFixture.encode(
            OpenSkySaveFixture.snapshot([], bystanderCell: OpenSkySaveFixture.riverwood)
        )
        #expect(data.range(of: Data("HRVS".utf8)) == nil)
    }

    /// The day survives, so a plant whose cell has not reset stays harvested after a load.
    @Test func aTimedHarvestKeepsItsDay() throws {
        let timed = ReferenceHarvestState(isHarvested: true, harvestedOnDay: 4.5)
        let original = OpenSkySaveFixture.snapshot(
            [
                OpenSkySaveFixture.entry(
                    key: plant, cell: OpenSkySaveFixture.whiterun, components: [timed.erased]
                )
            ],
            bystanderCell: OpenSkySaveFixture.riverwood
        )
        let data = OpenSkySaveFixture.encode(original)
        #expect(data.range(of: Data("HRVD".utf8)) != nil)
        let file = try OpenSkySaveDecoder.decode(data)
        #expect(file.snapshot == original)
        let store = WorldStateStore()
        store.restore(from: file.snapshot)
        let restored = store.component(ReferenceHarvestState.self, for: plant)
        #expect(restored == timed)
        #expect(HarvestRegrowth.vanilla.isHarvested(restored, onDay: 10))
        #expect(!HarvestRegrowth.vanilla.isHarvested(restored, onDay: 14.5))
    }

    @Test func anUntimedHarvestWritesNoDayChunk() {
        let data = OpenSkySaveFixture.encode(snapshot())
        #expect(data.range(of: Data("HRVD".utf8)) == nil)
    }
}
