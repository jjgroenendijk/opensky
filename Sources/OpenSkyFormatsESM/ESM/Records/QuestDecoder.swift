// The QUST grouping state machine, quest level; ordering rules are in
// Quest.swift. A marker field closes the group it replaces and opens the next.
// What the walk cannot place goes to `tally` instead of throwing, because a
// quest that loses one alias is still usable. Members are internal so the
// satellite files can read them.

import Foundation
import OpenSkyFormatsCore

nonisolated extension Quest {
    public struct Contents: Sendable {
        public let localized: Bool

        public var editorID: String?
        public var name: LString?
        public var flags = Flags()
        public var priority: UInt8 = 0
        public var kind = Kind.none
        public var event: FourCC?
        public var textDisplayGlobals: [FormID] = []
        public var objectWindowFilter: String?
        public var dialogueConditions = ConditionList()
        public var storyManagerConditions = ConditionList()
        public var stages: [Stage] = []
        public var objectives: [Objective] = []
        public var nextAliasID: UInt32?
        public var aliases: [Alias] = []
        public var questDescription: String?
        public var legacyTargets: [Target] = []
        public var script = ScriptData(ownerType: "QUST")
        public var tally = QuestTally()

        /// NEXT: the CTDA run before it is the quest's dialogue condition set,
        /// the run after it belongs to the story manager.
        public var sawConditionSeparator = false
        /// ANAM: ends the objective run and opens the alias run, which is also
        /// what disambiguates the trailing NNAM and QSTA fields.
        public var sawAliasMarker = false
        public var openStage: Stage?
        public var openLogEntry: LogEntry?
        public var openObjective: Objective?
        public var openTarget: Target?
        public var openAlias: Alias?

        public init(localized: Bool) {
            self.localized = localized
        }

        public mutating func decode(field: ESMField) throws {
            switch field.type {
            case "ALST":
                try beginAlias(field, category: .reference)
            case "ALLS":
                try beginAlias(field, category: .location)
            case "ALED":
                endAlias(terminated: true)
            default:
                if openAlias != nil {
                    try decodeAliasField(field)
                } else {
                    try decodeQuestField(field)
                }
            }
        }

        /// Flushes every group still open at the end of the field run.
        public mutating func closeOpenGroups() {
            endAlias(terminated: false)
            flushObjective()
            flushStage()
        }

        private mutating func decodeQuestField(_ field: ESMField) throws {
            if try decodeGroupMarker(field) {
                return
            }
            if try decodeHeader(field) {
                return
            }
            if try routeConditions(field) {
                return
            }
            tally.note(.unknownField(field.type))
        }

        /// The fields that open or extend one of the grouped runs. One branch
        /// per marker: the branches are the layout, and merging them would
        /// obscure it.
        private mutating func decodeGroupMarker(_ field: ESMField) throws -> Bool {
            switch field.type {
            case "INDX":
                try beginStage(field)
            case "QSDT":
                try beginLogEntry(field)
            case "CNAM":
                try setLogEntryText(field)
            case "NAM0":
                try setNextQuest(field)
            case "QOBJ":
                try beginObjective(field)
            case "FNAM":
                try setObjectiveFlags(field)
            case "NNAM":
                try setDisplayTextOrDescription(field)
            case "QSTA":
                try beginTarget(field)
            default:
                return false
            }
            return true
        }

        private mutating func decodeHeader(_ field: ESMField) throws -> Bool {
            var reader = BinaryReader(field.data)
            switch field.type {
            case "EDID":
                editorID = try reader.readZString()
            case "VMAD":
                try script.decode(field: field)
            case "FULL":
                name = try LString(field: field, localized: localized)
            case "DNAM":
                try decodeGeneralData(field)
            case "ENAM":
                guard field.data.count >= 4 else { return note(.malformedField(field.type)) }
                event = try reader.readFourCC()
            case "QTGL":
                guard field.data.count >= 4 else { return note(.malformedField(field.type)) }
                try textDisplayGlobals.append(FormID(reader.readUInt32()))
            case "FLTR":
                objectWindowFilter = try reader.readZString()
            case "NEXT":
                sawConditionSeparator = true
            case "ANAM":
                try beginAliasRun(field)
            default:
                return false
            }
            return true
        }

        /// DNAM, 12 bytes: uint16 flags, uint8 priority, uint8 form version,
        /// 4 unused bytes, uint32 quest type.
        private mutating func decodeGeneralData(_ field: ESMField) throws {
            guard field.data.count >= 12 else {
                tally.note(.malformedField(field.type))
                return
            }
            var reader = BinaryReader(field.data)
            flags = try Flags(rawValue: reader.readUInt16())
            priority = try reader.readUInt8()
            reader.skip(1) // form version, echoed from the record header
            reader.skip(4) // unused
            kind = try Kind(rawValue: reader.readUInt32())
        }

        /// ANAM ends the stage and objective runs and opens the alias run.
        private mutating func beginAliasRun(_ field: ESMField) throws {
            flushObjective()
            flushStage()
            sawAliasMarker = true
            guard field.data.count >= 4 else {
                tally.note(.malformedField(field.type))
                return
            }
            var reader = BinaryReader(field.data)
            nextAliasID = try reader.readUInt32()
        }

        /// Sends a condition-run field to the innermost group that owns one.
        private mutating func routeConditions(_ field: ESMField) throws -> Bool {
            if var target = openTarget {
                let handled = try target.conditions.decode(field: field)
                openTarget = target
                return handled
            }
            if var entry = openLogEntry {
                let handled = try entry.conditions.decode(field: field)
                openLogEntry = entry
                return handled
            }
            if sawConditionSeparator {
                return try storyManagerConditions.decode(field: field)
            }
            return try dialogueConditions.decode(field: field)
        }

        /// Records a skip and reports the field as handled, so a malformed or
        /// misplaced subrecord costs one entry instead of falling through into
        /// another group's reading of the same four letters.
        @discardableResult
        public mutating func note(_ kind: QuestSkipKind) -> Bool {
            tally.note(kind)
            return true
        }
    }
}
