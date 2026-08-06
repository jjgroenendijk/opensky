// QUST, the quest record: journal stages, objectives, and the alias slots the
// quest resolves world objects through.
//
// QUST is the most order-dependent record in the plugin format. Almost nothing
// in it is a self-describing struct; instead a marker subrecord opens a group
// and every following subrecord belongs to that group until the next marker.
// Three of those sequences stack up:
//
//   INDX        opens a quest stage; QSDT opens a log entry inside it, and the
//               log entry owns the CTDA run, the CNAM journal text and NAM0.
//   QOBJ        opens an objective; FNAM and NNAM describe it and each QSTA
//               opens a target that owns its own CTDA run.
//   ALST/ALLS   opens an alias (reference or location); ALED closes it, and
//               everything between belongs to that alias — including FNAM,
//               CTDA, KSIZ/KWDA and COCT/CNTO, all of which mean something
//               different at quest level.
//
// The decoder therefore keeps explicit open-group state rather than a flat
// field switch, and the three accumulators live in QuestDecoder.swift. Two
// separator fields drive the rest: NEXT splits the quest's own dialogue
// conditions from its story-manager event conditions, and ANAM ends the
// objective run and begins the alias run — which is also what makes the
// trailing NNAM the quest description rather than an objective's display text.
//
// Ambiguity policy, from the same rule the rest of the record decoders follow:
// a wrong-size subrecord costs its own entry, a subrecord that arrives with no
// group open costs itself, and an unknown or later-game subrecord is skipped.
// All three are counted in `QuestTally` so a sweep can assert zero instead of
// discovering the loss silently. Only a non-QUST record throws.
//
// The stage scripts are *not* here. They live in the QUST tail of the VMAD
// field, decoded into `QuestFragmentSection`; `fragments` surfaces them.
//
// References:
//   UESP "Skyrim Mod:Mod File Format/QUST"
//     https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/QUST
//   xEdit dev-4.1.6 Core/wbDefinitionsTES5.pas, `wbRecord(QUST, 'Quest', ...)`
//     line 8759: DNAM 8763, stages 8797, objectives 8840, aliases 8869
//     (reference) and 8971 (location).
// Layout documented in docs/formats/records.md.

import Foundation

nonisolated struct Quest {
    /// DNAM's leading uint16. UESP splits the same two bytes into a pair of
    /// uint8 flag fields and names only five of the bits; xEdit names all
    /// sixteen, and those names are used here.
    struct Flags: OptionSet, Equatable {
        let rawValue: UInt16

        static let startGameEnabled = Flags(rawValue: 1 << 0)
        static let completed = Flags(rawValue: 1 << 1)
        static let addIdleTopicToHello = Flags(rawValue: 1 << 2)
        static let allowRepeatedStages = Flags(rawValue: 1 << 3)
        static let startsEnabled = Flags(rawValue: 1 << 4)
        static let displayedInHUD = Flags(rawValue: 1 << 5)
        static let failed = Flags(rawValue: 1 << 6)
        static let stageWait = Flags(rawValue: 1 << 7)
        static let runOnce = Flags(rawValue: 1 << 8)
        static let excludeFromDialogueExport = Flags(rawValue: 1 << 9)
        static let warnOnAliasFillFailure = Flags(rawValue: 1 << 10)
        static let active = Flags(rawValue: 1 << 11)
        static let repeatsConditions = Flags(rawValue: 1 << 12)
        static let keepInstance = Flags(rawValue: 1 << 13)
        static let wantDormant = Flags(rawValue: 1 << 14)
        static let hasDialogueData = Flags(rawValue: 1 << 15)
    }

    /// DNAM's trailing uint32. Type 0 keeps the quest out of the journal
    /// entirely, and type 6 shows only its objectives, which is what makes the
    /// census's "miscellaneous" bucket the cheapest journal surface to target.
    enum Kind: Equatable {
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

        // One branch per documented value; a lookup table would not read
        // better than the list, so the complexity cap is waived here.
        // swiftlint:disable:next cyclomatic_complexity
        init(rawValue: UInt32) {
            switch rawValue {
            case 0: self = .none
            case 1: self = .mainQuest
            case 2: self = .magesGuild
            case 3: self = .thievesGuild
            case 4: self = .darkBrotherhood
            case 5: self = .companionQuests
            case 6: self = .miscellaneous
            case 7: self = .daedricQuests
            case 8: self = .sideQuests
            case 9: self = .civilWar
            case 10: self = .vampire
            case 11: self = .dragonborn
            default: self = .unknown(rawValue)
            }
        }

        var name: String {
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

    let formID: FormID
    let editorID: String?
    /// FULL. Hidden by the journal for a miscellaneous quest, which shows only
    /// its objectives.
    let name: LString?
    let flags: Flags
    /// 0...100 in the Creation Kit; the higher-priority quest owns a shared
    /// alias when two quests want the same reference.
    let priority: UInt8
    let kind: Kind
    /// ENAM, the story-manager event this quest starts from. Matches an SMEN
    /// short name; carried raw because the story manager is not modelled.
    let event: FourCC?
    /// QTGL, the globals the journal text may substitute into.
    let textDisplayGlobals: [FormID]
    /// FLTR, the Creation Kit's Object Window folder path. Authoring metadata.
    let objectWindowFilter: String?
    /// The CTDA run before NEXT: whether the quest's dialogue is available.
    let dialogueConditions: ConditionList
    /// The CTDA run after NEXT: the story-manager node conditions.
    let storyManagerConditions: ConditionList
    /// Stages in file order. Stage indices are not unique within a quest.
    let stages: [Stage]
    /// Objectives in file order. Objective indices are not unique either.
    let objectives: [Objective]
    /// ANAM, the Creation Kit's next-free alias ID counter.
    let nextAliasID: UInt32?
    let aliases: [Alias]
    /// The NNAM that follows the alias run — a plain zstring, unlike the
    /// objective NNAM, and unused by shipped Skyrim data.
    let questDescription: String?
    /// Record-level QSTA targets, a pre-alias form kept for compatibility.
    /// Their `alias` word is a direct reference FormID, not an alias ID.
    let legacyTargets: [Target]
    /// VMAD, including the decoded QUST fragment tail.
    let script: ScriptData
    let skipped: QuestTally

    /// Quest-stage script fragments, from the VMAD tail rather than the stage
    /// subrecords. Empty when the quest has no stage scripts, and also when
    /// its fragment tail failed to decode (`script.skipped` records that).
    var fragments: [QuestFragment] {
        script.questFragments?.fragments ?? []
    }

    /// Scripts attached to this quest's aliases, likewise from the VMAD tail.
    var aliasScripts: [QuestAliasScripts] {
        script.questFragments?.aliasScripts ?? []
    }

    /// The alias `id` names, or nil when the quest defines no such alias.
    func alias(id: UInt32) -> Alias? {
        aliases.first { $0.id == id }
    }

    /// Stages carrying at least one journal log entry — the ones a journal UI
    /// can actually display.
    var journalStages: [Stage] {
        stages.filter { stage in stage.logEntries.contains { $0.text != nil } }
    }

    init(record: ESMRecord, localized: Bool = false) throws {
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
nonisolated enum QuestSkipKind: Hashable {
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

    var name: String {
        switch self {
        case let .unknownField(type): "unknown \(type)"
        case let .malformedField(type): "malformed \(type)"
        case let .orphanField(type): "orphan \(type)"
        case .unterminatedAlias: "unterminated alias"
        }
    }
}

nonisolated struct QuestTally: Equatable {
    private(set) var counts: [QuestSkipKind: Int] = [:]

    var total: Int {
        counts.values.reduce(0, +)
    }

    var isEmpty: Bool {
        counts.isEmpty
    }

    var ranked: [(name: String, count: Int)] {
        counts
            .sorted {
                $0.value == $1.value
                    ? $0.key.name < $1.key.name
                    : $0.value > $1.value
            }
            .map { ($0.key.name, $0.value) }
    }

    mutating func note(_ kind: QuestSkipKind, count: Int = 1) {
        counts[kind, default: 0] += count
    }

    mutating func merge(_ other: QuestTally) {
        for (kind, count) in other.counts {
            note(kind, count: count)
        }
    }
}
