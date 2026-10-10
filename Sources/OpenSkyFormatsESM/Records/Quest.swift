// QUST: journal stages, objectives, and alias slots. Marker subrecords (INDX,
// QSDT, QOBJ, QSTA, ALST/ALLS...ALED) open groups that own what follows, so
// QuestDecoder.swift keeps open-group state. Bad subrecords cost only
// themselves and are counted in `QuestTally`. Stage scripts come from VMAD.
// Layout: docs/formats/quest-records.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct Quest: Sendable {
    /// DNAM's leading uint16. Names follow xEdit; only the bits OpenSky reads
    /// are declared.
    public struct Flags: OptionSet, Equatable, Sendable {
        public let rawValue: UInt16

        public init(rawValue: UInt16) {
            self.rawValue = rawValue
        }

        public static let startGameEnabled = Flags(rawValue: 1 << 0)
        public static let runOnce = Flags(rawValue: 1 << 8)
    }

    /// DNAM's trailing uint32. Type 0 keeps the quest out of the journal
    /// entirely, and type 6 shows only its objectives, which is what makes the
    /// census's "miscellaneous" bucket the cheapest journal surface to target.
    public enum Kind: Equatable, Sendable {
        case none
        case mainQuest
        case magesGuild
        case thievesGuild
        case darkBrotherhood
        case companionQuests
        case miscellaneous
        case daedricQuests
        case sideQuests
        case civilWar
        case vampire
        case dragonborn
        case unknown(UInt32)

        /// Indexed by the raw DNAM value.
        private static let known: [Kind] = [
            .none, .mainQuest, .magesGuild, .thievesGuild, .darkBrotherhood, .companionQuests,
            .miscellaneous, .daedricQuests, .sideQuests, .civilWar, .vampire, .dragonborn
        ]

        public init(rawValue: UInt32) {
            let index = Int(rawValue)
            self = index < Self.known.count ? Self.known[index] : .unknown(rawValue)
        }

        public var name: String {
            switch self {
            case .none: "none"
            case .mainQuest: "main quest"
            case .magesGuild: "mages guild"
            case .thievesGuild: "thieves guild"
            case .darkBrotherhood: "dark brotherhood"
            case .companionQuests: "companions"
            case .miscellaneous: "miscellaneous"
            case .daedricQuests: "daedric"
            case .sideQuests: "side quest"
            case .civilWar: "civil war"
            case .vampire: "vampire"
            case .dragonborn: "dragonborn"
            case let .unknown(raw): "unknown(\(raw))"
            }
        }
    }

    /// The FormID as its plugin writes it, unless a load-order store renumbered it
    /// with `renumbered(_:)`.
    public private(set) var formID: FormID
    public let editorID: String?
    /// FULL. Hidden by the journal for a miscellaneous quest, which shows only
    /// its objectives.
    public let name: LString?
    public let flags: Flags
    /// 0...100 in the Creation Kit; the higher-priority quest owns a shared
    /// alias when two quests want the same reference.
    public let priority: UInt8
    public let kind: Kind
    /// ENAM, the story-manager event this quest starts from. Matches an SMEN
    /// short name; carried raw because the story manager is not modelled.
    public let event: FourCC?
    /// QTGL, the globals the journal text may substitute into.
    public let textDisplayGlobals: [FormID]
    /// FLTR, the Creation Kit's Object Window folder path. Authoring metadata.
    public let objectWindowFilter: String?
    /// The CTDA run before NEXT: whether the quest's dialogue is available.
    public let dialogueConditions: ConditionList
    /// The CTDA run after NEXT: the story-manager node conditions.
    public let storyManagerConditions: ConditionList
    /// Stages in file order. Stage indices are not unique within a quest.
    public let stages: [Stage]
    /// Objectives in file order. Objective indices are not unique either.
    public let objectives: [Objective]
    /// ANAM, the Creation Kit's next-free alias ID counter.
    public let nextAliasID: UInt32?
    public let aliases: [Alias]
    /// The NNAM that follows the alias run — a plain zstring, unlike the
    /// objective NNAM, and unused by shipped Skyrim data.
    public let questDescription: String?
    /// Record-level QSTA targets, a pre-alias form kept for compatibility.
    /// Their `alias` word is a direct reference FormID, not an alias ID.
    public let legacyTargets: [Target]
    /// VMAD, including the decoded QUST fragment tail.
    public let script: ScriptData
    public let skipped: QuestTally

    /// Quest-stage script fragments, from the VMAD tail rather than the stage
    /// subrecords. Empty when the quest has no stage scripts, and also when
    /// its fragment tail failed to decode (`script.skipped` records that).
    public var fragments: [QuestFragment] {
        script.questFragments?.fragments ?? []
    }

    /// Scripts attached to this quest's aliases, likewise from the VMAD tail.
    public var aliasScripts: [QuestAliasScripts] {
        script.questFragments?.aliasScripts ?? []
    }

    /// The alias `id` names, or nil when the quest defines no such alias.
    public func alias(id: UInt32) -> Alias? {
        aliases.first { $0.id == id }
    }

    /// The same record under another FormID, for a store that numbers quests
    /// from several plugins in one space. The fields inside keep their own FormIDs.
    public func renumbered(_ id: FormID) -> Quest {
        var copy = self
        copy.formID = id
        return copy
    }

    /// Stages carrying at least one journal log entry — the ones a journal UI
    /// can actually display.
    public var journalStages: [Stage] {
        stages.filter { stage in stage.logEntries.contains { $0.text != nil } }
    }

    public init(record: ESMRecord, localized: Bool = false) throws {
        guard record.type == "QUST" else {
            throw ESMError.malformed("expected QUST record, got \(record.type)")
        }
        formID = FormID(record.formID)

        var contents = Contents(localized: localized)
        for field in try record.fields() {
            try contents.decode(field: field)
        }
        contents.closeOpenGroups()

        editorID = contents.editorID
        name = contents.name
        flags = contents.flags
        priority = contents.priority
        kind = contents.kind
        event = contents.event
        textDisplayGlobals = contents.textDisplayGlobals
        objectWindowFilter = contents.objectWindowFilter
        dialogueConditions = contents.dialogueConditions
        storyManagerConditions = contents.storyManagerConditions
        stages = contents.stages
        objectives = contents.objectives
        nextAliasID = contents.nextAliasID
        aliases = contents.aliases
        questDescription = contents.questDescription
        legacyTargets = contents.legacyTargets
        script = contents.script
        skipped = contents.tally
    }
}

/// Reason-tagged count of everything a QUST decode chose to drop, mirroring
/// `ScriptDataTally`. A sweep asserts against it; a single record's copy
/// explains why its stage or alias count came out lower than expected.
nonisolated public enum QuestSkipKind: SkipTallyKind {
    /// A subrecord this decoder does not model — a later-game addition, a
    /// Creation Kit leftover such as SCHR, or a modder's own field.
    case unknownField(FourCC)
    /// A subrecord too short for its documented layout.
    case malformedField(FourCC)
    /// A subrecord that belongs to a group nothing had opened.
    case orphanField(FourCC)
    /// An ALST/ALLS block that a new alias or the end of the record cut off
    /// before its ALED terminator arrived.
    case unterminatedAlias

    public var name: String {
        switch self {
        case let .unknownField(type): "unknown \(type)"
        case let .malformedField(type): "malformed \(type)"
        case let .orphanField(type): "orphan \(type)"
        case .unterminatedAlias: "unterminated alias"
        }
    }
}

public typealias QuestTally = SkipTally<QuestSkipKind>
