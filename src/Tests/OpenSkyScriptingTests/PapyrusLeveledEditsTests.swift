// The bridge hands the leveled-list changes scripts made to the roller its session gives it.

import OpenSkyFormatsESM
import OpenSkyGameData
@testable import OpenSkyScripting
import OpenSkyScriptingInterface
import OpenSkyWorldState
import Testing

@MainActor
struct PapyrusLeveledEditsTests {
    @Test func publishingReplacesTheEditsTheSessionHandsOver() {
        let edits = LeveledScriptEdits()
        edits.setAddedEntries([FormID(0x10): []])
        let before = edits.revision
        let bridge = PapyrusWorldStateBridge(worldState: WorldStateStore())
        bridge.sessionNatives.leveledEdits = { edits }

        bridge.publishLeveledEdits()

        #expect(edits.revision == before + 1)
    }

    @Test func aSessionWithoutLeveledListsPublishesNothing() {
        let bridge = PapyrusWorldStateBridge(worldState: WorldStateStore())
        bridge.publishLeveledEdits()
        #expect(bridge.sessionNatives.leveledEdits == nil)
    }
}
