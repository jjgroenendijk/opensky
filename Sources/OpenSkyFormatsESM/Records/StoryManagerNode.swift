// SMBN branch, SMQN quest, and SMEN event nodes of the story manager. Each node
// names its parent and its previous sibling, so the tree is rebuilt from links.
// Layout and sources: docs/formats/story-manager.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct StoryManagerNode: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case branch
        case quest
        case event
    }

    /// DNAM flag bits. Bits 16 to 18 are used by quest nodes only.
    public struct Flags: OptionSet, Equatable, Sendable {
        public let rawValue: UInt32

        public init(rawValue: UInt32) {
            self.rawValue = rawValue
        }

        public static let random = Flags(rawValue: 0x01)
        public static let warnIfNoChildQuestStarted = Flags(rawValue: 0x02)
        public static let doAllBeforeRepeating = Flags(rawValue: 0x0001_0000)
        public static let sharesEvent = Flags(rawValue: 0x0002_0000)
        public static let numberOfQuestsToRun = Flags(rawValue: 0x0004_0000)
    }

    /// One SMQN quest entry: NNAM, then optional FNAM and RNAM.
    public struct QuestEntry: Equatable, Sendable {
        public let quest: FormID
        /// FNAM: the reset timer runs for a full day.
        public var resetsAfterFullDay: Bool?
        /// RNAM, in game hours.
        public var hoursUntilReset: Float?
    }

    public static let recordTypes: Set<FourCC> = ["SMBN", "SMQN", "SMEN"]

    public let formID: FormID
    public let kind: Kind
    public let editorID: String?
    /// PNAM. Nil for a root node.
    public let parent: FormID?
    /// SNAM. Nil for a first child.
    public let previousSibling: FormID?
    public let conditions: [Condition]
    public let flags: Flags
    /// XNAM.
    public let maxConcurrentQuests: UInt32?
    /// SMQN MNAM.
    public let questsToRun: UInt32?
    /// SMQN QNAM, the authored count of `quests`.
    public let declaredQuestCount: UInt32?
    public let quests: [QuestEntry]
    /// SMEN ENAM, the event code such as `KILL`.
    public let event: FourCC?
    public let skipped: FieldTally

    public init(record: ESMRecord) throws {
        var fields = try RecordFields(record: record, types: Self.recordTypes)
        formID = fields.formID
        kind = switch record.type {
        case "SMQN": .quest
        case "SMEN": .event
        default: .branch
        }
        editorID = fields.editorID()
        parent = fields.formID("PNAM")
        previousSibling = fields.formID("SNAM")
        conditions = fields.conditions()
        flags = Flags(rawValue: fields.uint32("DNAM") ?? 0)
        maxConcurrentQuests = fields.uint32("XNAM")
        questsToRun = fields.uint32("MNAM")
        declaredQuestCount = fields.uint32("QNAM")
        event = fields.read("ENAM") { try $0.readFourCC() }
        quests = Self.questEntries(&fields)
        if let declaredQuestCount, Int(declaredQuestCount) != quests.count {
            fields.note(.mismatch("QNAM count differs from NNAM entries"))
        }
        skipped = fields.finish()
    }

    private static func questEntries(_ fields: inout RecordFields) -> [QuestEntry] {
        var entries: [QuestEntry] = []
        for index in fields.fields.indices {
            switch fields.fields[index].type {
            case "NNAM":
                if let quest = fields.read(at: index, { try $0.readFormID() }) {
                    entries.append(QuestEntry(quest: quest))
                }
            case "FNAM" where !entries.isEmpty:
                entries[entries.count - 1].resetsAfterFullDay =
                    fields.read(at: index) { try $0.readUInt32() != 0 }
            case "RNAM" where !entries.isEmpty:
                entries[entries.count - 1].hoursUntilReset =
                    fields.read(at: index) { try $0.readFloat32() }
            default:
                continue
            }
        }
        return entries
    }
}
