// Quest change forms with form flags, script delay, run data, and instances, which the
// import skips but must read to their end.

import FormatsTesting
import Foundation
import OpenSkyFormatsCore
@testable import OpenSkyFormatsESS
import TagsTesting
import Testing

@Suite(.tags(.parser))
struct ESSQuestChangeTests {
    private typealias Quest = ESSChangeFlag.Quest

    private static func quest(
        flags: UInt32, typeIndex: UInt8 = 8, _ body: (inout BinaryWriter) -> Void
    ) throws(ESSError) -> ESSQuestChange {
        try ESSQuestChange(ESSChangeForm(
            form: ESSRefID(kind: .default, value: 0x3372B), flags: flags, typeIndex: typeIndex,
            version: 74, data: ESSChangeFormData(stored: ESSBytes.build(body))
        ))
    }

    private static func runData(itemType: UInt32, _ writer: inout BinaryWriter) {
        writer.writeUInt8(0)
        writer.writeUInt32(2)
        writer.writeUInt32(1)
        writer.writeUInt8(0)
        writer.write(Data(count: 3))
        writer.writeUInt32(2)
        writer.writeUInt8(1)
        writer.write(Data(count: 15))
        writer.writeUInt32(1)
        writer.write(Data(count: 7))
        writer.writeUInt8(1)
        writer.write(Data(count: 8))
        writer.writeUInt32(2)
        writer.writeUInt32(itemType)
        writer.write(Data(count: 3))
        writer.writeUInt32(3)
        writer.writeUInt32(9)
    }

    @Test func runDataAndInstancesAreReadToTheirEnd() throws {
        let flags = ESSChangeFlag.formFlags | Quest.scriptDelay | Quest.runData
            | Quest.instances | Quest.alreadyRun
        let change = try Self.quest(flags: flags) { writer in
            writer.writeUInt32(0x20)
            writer.writeUInt16(0)
            writer.writeFloat32(5)
            Self.runData(itemType: 1, &writer)
            writer.writeUInt32(0)
            ESSBytes.vsval(1, into: &writer)
            writer.writeUInt32(4)
            ESSBytes.vsval(1, into: &writer)
            writer.write(Data(count: 7))
            ESSBytes.vsval(0, into: &writer)
            writer.write(Data(count: 3))
            writer.writeUInt8(0)
        }
        #expect(change.status == .complete)
        #expect(change.form == ESSRefID(kind: .default, value: 0x3372B))
        #expect(change.formFlags == 0x20)
        #expect(change.scriptDelay == 5)
        #expect(change.alreadyRun == false)
    }

    @Test func objectivesKeepBothStoredWords() throws {
        let change = try Self.quest(flags: Quest.objectives) { writer in
            ESSBytes.vsval(1, into: &writer)
            writer.writeUInt32(10)
            writer.writeUInt32(3)
        }
        #expect(change.objectives?.first?.first == 10)
        #expect(change.objectives?.first?.second == 3)
    }

    @Test func aSaidOnceTopicKeepsItsFormAndFlag() throws {
        let topic = try ESSTopicChange(ESSChangeForm(
            form: ESSRefID(kind: .default, value: 0x2), flags: ESSChangeFlag.Topic.saidOnce,
            typeIndex: 7, version: 74, data: ESSChangeFormData(stored: Data())
        ))
        #expect(topic.form == ESSRefID(kind: .default, value: 0x2))
        #expect(topic.saidOnce)
    }

    @Test func unknownRunDataItemThrows() {
        #expect(throws: ESSError.self) {
            try Self.quest(flags: Quest.runData) { Self.runData(itemType: 9, &$0) }
        }
    }

    @Test func leftoverBytesWithoutScriptAreReported() throws {
        let change = try Self.quest(flags: Quest.flags) { writer in
            writer.writeUInt16(1)
            writer.writeUInt8(0)
        }
        #expect(change.status == .partial(blockedBy: "unread bytes (1 bytes)"))
    }

    @Test func otherChangeTypesAreRejected() {
        #expect(throws: ESSError.self) {
            try Self.quest(flags: 0, typeIndex: 0) { _ in }
        }
        #expect(throws: ESSError.self) {
            try ESSTopicChange(ESSChangeForm(
                form: ESSRefID(kind: .default, value: 1), flags: 0, typeIndex: 8, version: 74,
                data: ESSChangeFormData(stored: Data())
            ))
        }
    }
}
