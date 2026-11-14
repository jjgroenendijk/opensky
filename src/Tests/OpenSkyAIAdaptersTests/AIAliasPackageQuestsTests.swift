// The running quests whose aliases carry packages, in the order their stacks fill.

import Foundation
@testable import OpenSkyAIAdapters
import OpenSkyFormatsESM
import OpenSkyFormatsTesting
import OpenSkyWorldState
import Testing

@MainActor
struct AIAliasPackageQuestsTests {
    private static func quest(_ formID: UInt32, priority: UInt8, package: UInt32?) throws -> Quest {
        let extras = package.map { QuestFixture.word("ALPC", $0) } ?? Data()
        return try QuestFixture.quest(
            formID: formID,
            fields: QuestFixture.general(priority: priority)
                + QuestFixture.alias(id: 0, name: "Guard", extras: extras)
        )
    }

    @Test func keepsQuestsWithAliasPackagesHighestPriorityFirst() throws {
        let running = try [
            (Self.quest(0x10, priority: 20, package: 0x900), ReferenceKey.player),
            (Self.quest(0x11, priority: 60, package: nil), ReferenceKey.player),
            (Self.quest(0x12, priority: 50, package: 0x901), ReferenceKey.player)
        ].map { (quest: $0.0, key: $0.1) }
        let quests = AIPackageMovesAdapter.Places.aliasPackageQuests(running)
        #expect(quests.map(\.formID.rawValue) == [0x12, 0x10])
    }
}
