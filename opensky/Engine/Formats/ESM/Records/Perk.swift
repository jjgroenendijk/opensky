// PERK, the record behind every perk the player picks and every passive an
// actor carries. A perk is a header, an availability condition run, and a list
// of typed effects: set a quest stage, grant an ability spell, or hook an
// entry point that combat and magic formulas query while they compute a value.
//
// PERK is field-order-dependent in the same way QUST is. PRKE opens an effect
// and PRKF closes it, which is what disambiguates the two meanings of DATA
// (the record's five-byte header before the first PRKE, the effect's typed
// payload after one) and the two meanings of a CTDA run (the perk's own
// availability conditions before the first PRKE, an entry-point condition tab
// after one). The decoder therefore keeps explicit open-effect state; it lives
// in PerkDecoder.swift, and the effect types in PerkEffect.swift.
//
// Ambiguity policy follows QUST: a wrong-size subrecord costs its own entry, a
// subrecord that arrives with no effect open costs itself, and an unknown
// subrecord is skipped. All three are counted in `PerkTally` so a sweep can
// assert zero rather than discover the loss silently. Only a non-PERK record
// throws.
//
// References:
//   UESP "Skyrim Mod:Mod File Format/PERK"
//     https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/PERK
//   xEdit dev-4.1.6 Core/wbDefinitionsTES5.pas, `wbRecord(PERK, 'Perk', ...)`
//     line 5908.
// Layout and real-install evidence: docs/formats/perks.md.

import Foundation

nonisolated enum PerkSkipKind: Hashable {
    case unknownField(FourCC)
    case malformedField(FourCC)
    /// An effect-only subrecord (DATA payload, PRKC, EPFT, EPFD, ...) that
    /// arrived while no PRKE section was open.
    case fieldOutsideEffect(FourCC)
    /// A CTDA inside an effect that no PRKC had opened a tab for.
    case conditionOutsideTab
    /// An effect that ran to the end of the record without its PRKF marker.
    case unterminatedEffect

    var name: String {
        switch self {
        case let .unknownField(type): "unknown \(type)"
        case let .malformedField(type): "malformed \(type)"
        case let .fieldOutsideEffect(type): "stray \(type)"
        case .conditionOutsideTab: "condition outside tab"
        case .unterminatedEffect: "unterminated effect"
        }
    }
}

nonisolated struct PerkTally: Equatable {
    private(set) var counts: [PerkSkipKind: Int] = [:]

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

    mutating func note(_ kind: PerkSkipKind, count: Int = 1) {
        counts[kind, default: 0] += count
    }

    mutating func merge(_ other: PerkTally) {
        for (kind, count) in other.counts {
            note(kind, count: count)
        }
    }
}

/// DATA at record level: five bytes, one per field. UESP and xEdit agree on
/// the order — trait, level, rank count, playable, hidden — and vanilla reads
/// back consistently under it: every perk drawn in a skill tree is playable,
/// and the records that are not are the hidden ones quests and scripts add.
///
/// Two of the five fields mean less than their names suggest, measured across
/// the vanilla load order in `PerkRealDataTests`: `level` is zero on every
/// record (a perk's skill requirement is a condition on the record, not a
/// header field), and `rankCount` does not track the NNAM chain — `Armsman00`
/// declares 1 while its chain is five records long. xEdit recomputes the rank
/// count it displays after load, which is why its editor disagrees with the
/// bytes. Both are exposed verbatim; anything wanting the ranks walks the
/// chain through `PerkStore.rankChain(from:)`.
nonisolated struct PerkHeaderData: Equatable {
    static let byteCount = 5

    let isTrait: Bool
    /// Minimum skill level the perk needs, 0 on a perk with no requirement.
    let level: UInt8
    /// The declared rank count, verbatim. Vanilla mostly authors 1 regardless
    /// of how many ranks the perk really has — see the note above.
    let rankCount: UInt8
    let isPlayable: Bool
    let isHidden: Bool

    init(field: ESMField) throws {
        guard field.data.count >= Self.byteCount else {
            throw ESMError.malformed(
                "PERK DATA has \(field.data.count) bytes, expected \(Self.byteCount)"
            )
        }
        var reader = BinaryReader(field.data)
        isTrait = try reader.readUInt8() != 0
        level = try reader.readUInt8()
        rankCount = try reader.readUInt8()
        isPlayable = try reader.readUInt8() != 0
        isHidden = try reader.readUInt8() != 0
    }

    init(
        isTrait: Bool,
        level: UInt8,
        rankCount: UInt8,
        isPlayable: Bool,
        isHidden: Bool
    ) {
        self.isTrait = isTrait
        self.level = level
        self.rankCount = rankCount
        self.isPlayable = isPlayable
        self.isHidden = isHidden
    }
}

nonisolated struct Perk {
    let formID: FormID
    let editorID: String?
    let name: LString?
    let description: LString?
    let iconPath: String?
    /// The record-level CTDA run: whether the perk is available to be taken.
    let conditions: ConditionList
    /// Nil when the record carried no DATA or a truncated one; the effects are
    /// still decoded, because a perk with an unreadable header is still what a
    /// runtime formula queries.
    let data: PerkHeaderData?
    /// NNAM, the next rank of this perk. Null links decode to nil.
    let nextPerk: FormID?
    let effects: [PerkEffect]
    let script: ScriptData
    let skipped: PerkTally

    /// The rank count the record declares, defaulting to one when DATA did not
    /// decode. Not the number of ranks the perk actually has: that is the
    /// length of its NNAM chain, which `PerkStore.rankChain(from:)` walks.
    var declaredRankCount: UInt8 {
        max(data?.rankCount ?? 1, 1)
    }

    var isPlayable: Bool {
        data?.isPlayable ?? false
    }

    /// Every effect that hooks an entry point, in record order.
    var entryPointEffects: [PerkEffect] {
        effects.filter { $0.entryPoint != nil }
    }

    init(record: ESMRecord, localized: Bool) throws {
        guard record.type == "PERK" else {
            throw ESMError.malformed("expected PERK record, got \(record.type)")
        }
        var contents = PerkContents(localized: localized)
        for field in try record.fields() {
            contents.decode(field)
        }
        contents.closeOpenEffect(terminated: false)
        formID = FormID(record.formID)
        editorID = contents.editorID
        name = contents.name
        description = contents.description
        iconPath = contents.iconPath
        conditions = contents.conditions
        data = contents.data
        nextPerk = contents.nextPerk
        effects = contents.effects
        script = contents.script
        skipped = contents.skipped
    }
}
