// RDMG chunk: the model or damage stage a destruction stage set comes back, and a session with no
// damaged object writes no chunk.

import Foundation
import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkySave
import OpenSkySaveFixtures
@testable import OpenSkyWorldState
import Testing

@MainActor
struct DamageModelSaveTests {
    private let barrel = ReferenceKey.plugin(name: "dragonborn.esm", objectID: 0x0001_B131)
    private let broken = ReferenceDamageModel(path: "dlc02\\barrel01broken.nif")

    @Test func aDamageModelSurvivesAnEncodeAndDecode() throws {
        let original = OpenSkySaveFixture.snapshot(
            [
                OpenSkySaveFixture.entry(
                    key: barrel,
                    cell: .exterior(CellCoordinate(x: 5, y: -24)),
                    components: [broken.erased]
                )
            ],
            bystanderCell: OpenSkySaveFixture.riverwood
        )
        let data = OpenSkySaveFixture.encode(original)
        #expect(data.range(of: Data("RDMG".utf8)) != nil)
        let file = try OpenSkySaveDecoder.decode(data)
        #expect(file.snapshot == original)
        #expect(file.snapshot[barrel]?.component(ReferenceDamageModel.self) == broken)
    }

    @Test func aDamageStageWithoutAModelSurvivesAnEncodeAndDecode() throws {
        let staged = ReferenceDamageModel(path: nil, stage: 1)
        let original = OpenSkySaveFixture.snapshot(
            [
                OpenSkySaveFixture.entry(
                    key: barrel,
                    cell: .exterior(CellCoordinate(x: 5, y: -24)),
                    components: [staged.erased]
                )
            ],
            bystanderCell: OpenSkySaveFixture.riverwood
        )
        let file = try OpenSkySaveDecoder.decode(OpenSkySaveFixture.encode(original))
        #expect(file.snapshot[barrel]?.component(ReferenceDamageModel.self) == staged)
    }

    @Test func noDamageModelWritesNoChunk() {
        let data = OpenSkySaveFixture.encode(
            OpenSkySaveFixture.snapshot([], bystanderCell: OpenSkySaveFixture.riverwood)
        )
        #expect(data.range(of: Data("RDMG".utf8)) == nil)
    }
}
