// The `.seq` start-game quest list over synthetic bytes. Layout: docs/formats/seq.md.

import Foundation
@testable import OpenSkyFormatsESM
import TagsTesting
import Testing

@Suite(.tags(.parser))
struct StartGameQuestListTests {
    @Test func readsLittleEndianFormIDsInOrder() throws {
        let list = try StartGameQuestList(data: Data([1, 0, 0, 0, 2, 0, 0, 1]))
        #expect(list.quests == [FormID(1), FormID(0x0100_0002)])
        #expect(try StartGameQuestList(data: Data()).quests.isEmpty)
    }

    @Test func rejectsATruncatedFile() {
        #expect(throws: StartGameQuestListError.truncated(byteCount: 3)) {
            try StartGameQuestList(data: Data([1, 2, 3]))
        }
    }

    @Test func namesThePathAfterThePlugin() {
        #expect(StartGameQuestList.path(forPlugin: "Skyrim.esm") == "seq\\Skyrim.seq")
    }
}
