// DLBR dialogue branch and DLVW dialogue view. A branch groups the topics a
// quest offers from one starting topic; a view lists branches for the editor.
// Layout and sources: docs/formats/dialogue.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct DialogueBranch: Equatable, Sendable {
    /// DNAM flag bits.
    public struct Flags: OptionSet, Equatable, Sendable {
        public let rawValue: UInt32

        public init(rawValue: UInt32) {
            self.rawValue = rawValue
        }

        public static let topLevel = Flags(rawValue: 0x01)
        public static let blocking = Flags(rawValue: 0x02)
        public static let exclusive = Flags(rawValue: 0x04)
    }

    public let formID: FormID
    public let editorID: String?
    /// QNAM, the owning QUST.
    public let quest: FormID?
    /// TNAM: 0 player, 1 favor. Other values are kept.
    public let category: UInt32?
    public let flags: Flags
    /// SNAM, the DIAL the branch starts with.
    public let startingTopic: FormID?
    public let skipped: FieldTally

    public init(record: ESMRecord) throws {
        var fields = try RecordFields(record: record, type: "DLBR")
        formID = fields.formID
        editorID = fields.editorID()
        quest = fields.formID("QNAM")
        category = fields.uint32("TNAM")
        flags = Flags(rawValue: fields.uint32("DNAM") ?? 0)
        startingTopic = fields.formID("SNAM")
        skipped = fields.finish()
    }
}

nonisolated public struct DialogueView: Equatable, Sendable {
    public let formID: FormID
    public let editorID: String?
    /// QNAM, the owning QUST.
    public let quest: FormID?
    /// BNAM, DLBR records in file order.
    public let branches: [FormID]
    /// TNAM, DIAL records in file order.
    public let topics: [FormID]
    /// ENAM topic type: player, favor, scene, combat, favors, detection, service, misc.
    public let topicType: UInt32?
    /// DNAM.
    public let showsAllText: Bool
    public let skipped: FieldTally

    public init(record: ESMRecord) throws {
        var fields = try RecordFields(record: record, type: "DLVW")
        formID = fields.formID
        editorID = fields.editorID()
        quest = fields.formID("QNAM")
        branches = fields.formIDs("BNAM")
        topics = fields.formIDs("TNAM")
        topicType = fields.uint32("ENAM")
        showsAllText = (fields.uint8("DNAM") ?? 0) != 0
        skipped = fields.finish()
    }
}
