// Active stack owners, frame instructions, and function messages, and the layouts that
// stop the stack read without failing the table.

import FormatsTesting
import Foundation
@testable import OpenSkyFormatsESS
import TagsTesting
import Testing

@Suite(.tags(.parser))
struct ESSPapyrusStackTests {
    private static func papyrus(_ edit: (inout ESSPapyrusFixture) -> Void) throws -> ESSPapyrus {
        var fixture = ESSPapyrusFixture()
        fixture.activeStacks = [(id: 7, script: "MQ101Script")]
        edit(&fixture)
        return try ESSPapyrus(data: fixture.build())
    }

    @Test(arguments: [("QuestStage", 6), ("SceneResults", 3), ("TopicInfo", 0)])
    func namedOwnerIsSkipped(name: String, tail: Int) throws {
        let papyrus = try Self.papyrus { $0.stackOwner = (name: name, tail: tail) }
        #expect(papyrus.stackStatus == .complete)
        #expect(papyrus.activeScriptNames[7] == "MQ101Script")
    }

    @Test func unknownOwnerStopsTheStacks() throws {
        let papyrus = try Self.papyrus { $0.stackOwner = (name: "Bogus", tail: 0) }
        #expect(!papyrus.stackStatus.isComplete)
    }

    @Test func instructionsAndMessagesAreSkipped() throws {
        let papyrus = try Self.papyrus { fixture in
            fixture.instructions = [
                Data([0x01, 3, 1, 0, 0, 0, 4, 0, 0, 0x80, 0x3F, 5, 1]),
                Data([0x17, 1, 0, 0, 0, 0, 3, 1, 0, 0, 0, 2, 1, 0]),
                Data([0x00])
            ]
            fixture.functionMessages = ["DefaultOnEnter"]
        }
        #expect(papyrus.stackStatus == .complete)
        #expect(papyrus.activeScriptNames[7] == "MQ101Script")
    }

    @Test(arguments: [Data([0x40]), Data([0x14, 9])])
    func unknownInstructionStopsTheStacks(instruction: Data) throws {
        let papyrus = try Self.papyrus { $0.instructions = [instruction] }
        #expect(!papyrus.stackStatus.isComplete)
        #expect(papyrus.activeScripts.map(\.id) == [7])
    }
}
