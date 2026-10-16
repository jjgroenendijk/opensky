// PLGD and PTRN chunks: legendary counts and training sessions ride beside the
// PLVL record and come back on the player's progress; nothing to save writes no chunk.

import Foundation
@testable import OpenSkyFormatsESM
import OpenSkyProgressionInterface
@testable import OpenSkySave
import OpenSkySaveFixtures
@testable import OpenSkyWorldState
import Testing

@MainActor
struct LegendarySkillSaveTests {
    private func snapshot(_ progress: PlayerProgressState) -> WorldStateSnapshot {
        OpenSkySaveFixture.snapshot(
            [
                OpenSkySaveFixture.entry(
                    key: .player, cell: OpenSkySaveFixture.whiterun, components: [progress.erased]
                )
            ],
            bystanderCell: OpenSkySaveFixture.riverwood
        )
    }

    @Test func legendaryCountsSurviveAnEncodeAndDecode() throws {
        let progress = PlayerProgressState(level: 30, perkPoints: 3, legendaryCounts: [6: 2, 18: 1])
        let data = OpenSkySaveFixture.encode(snapshot(progress))
        #expect(data.range(of: Data("PLGD".utf8)) != nil)

        let file = try OpenSkySaveDecoder.decode(data)
        let restored = file.snapshot[.player]?.component(PlayerProgressState.self)

        #expect(restored?.legendaryCount(ofSkill: 6) == 2)
        #expect(restored?.legendaryCount(ofSkill: 18) == 1)
        #expect(restored?.level == 30)
    }

    @Test func trainingSessionsSurviveAnEncodeAndDecode() throws {
        let progress = PlayerProgressState(level: 3).training().training()
        let data = OpenSkySaveFixture.encode(snapshot(progress))
        #expect(data.range(of: Data("PTRN".utf8)) != nil)

        let file = try OpenSkySaveDecoder.decode(data)
        let restored = file.snapshot[.player]?.component(PlayerProgressState.self)

        #expect(restored?.trainingSessions == 2)
        #expect(restored?.level == 3)
    }

    @Test func noLegendarySkillWritesNoChunk() {
        let data = OpenSkySaveFixture.encode(snapshot(PlayerProgressState(level: 4)))
        #expect(data.range(of: Data("PLGD".utf8)) == nil)
        #expect(data.range(of: Data("PTRN".utf8)) == nil)
        #expect(data.range(of: Data("PLVL".utf8)) != nil)
    }
}
