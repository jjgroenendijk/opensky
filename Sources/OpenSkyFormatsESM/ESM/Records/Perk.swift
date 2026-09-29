// PERK: a header, an availability condition run, and a list of typed effects.
// PRKE opens an effect and PRKF closes it, which decides what DATA and CTDA
// mean, so PerkDecoder.swift keeps open-effect state. Bad subrecords cost only
// themselves and are counted in `PerkTally`. Layout: docs/formats/perks.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public enum PerkSkipKind: Hashable, Sendable {
    case unknownField(FourCC)
    case malformedField(FourCC)
    /// An effect-only subrecord (DATA payload, PRKC, EPFT, EPFD, ...) that
    /// arrived while no PRKE section was open.
    case fieldOutsideEffect(FourCC)
    /// A CTDA inside an effect that no PRKC had opened a tab for.
    case conditionOutsideTab
    /// An effect that ran to the end of the record without its PRKF marker.
    case unterminatedEffect

    public var name: String {
        switch self {
        case let .unknownField(type): "unknown \(type)"
        case let .malformedField(type): "malformed \(type)"
        case let .fieldOutsideEffect(type): "stray \(type)"
        case .conditionOutsideTab: "condition outside tab"
        case .unterminatedEffect: "unterminated effect"
        }
    }
}

nonisolated public struct PerkTally: Equatable, Sendable {
    public private(set) var counts: [PerkSkipKind: Int] = [:]

    public var total: Int {
        counts.values.reduce(0, +)
    }

    public var isEmpty: Bool {
        counts.isEmpty
    }

    public var ranked: [(name: String, count: Int)] {
        counts
            .sorted {
                $0.value == $1.value
                    ? $0.key.name < $1.key.name
                    : $0.value > $1.value
            }
            .map { ($0.key.name, $0.value) }
    }

    public mutating func note(_ kind: PerkSkipKind, count: Int = 1) {
        counts[kind, default: 0] += count
    }

    public mutating func merge(_ other: PerkTally) {
        for (kind, count) in other.counts {
            note(kind, count: count)
        }
    }
}

/// Record-level DATA: trait, level, rank count, playable, hidden. Measured on
/// vanilla, `level` is always 0 and `rankCount` does not track the NNAM chain;
/// walk `PerkStore.rankChain(from:)` for ranks.
nonisolated public struct PerkHeaderData: Equatable, Sendable {
    public static let byteCount = 5

    public let isTrait: Bool
    /// Minimum skill level the perk needs, 0 on a perk with no requirement.
    public let level: UInt8
    /// The declared rank count, verbatim. Vanilla mostly authors 1 regardless
    /// of how many ranks the perk really has — see the note above.
    public let rankCount: UInt8
    public let isPlayable: Bool
    public let isHidden: Bool

    public init(field: ESMField) throws {
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
}

nonisolated public struct Perk: Sendable {
    public let formID: FormID
    public let editorID: String?
    public let name: LString?
    public let description: LString?
    public let iconPath: String?
    /// The record-level CTDA run: whether the perk is available to be taken.
    public let conditions: ConditionList
    /// Nil when the record carried no DATA or a truncated one; the effects are
    /// still decoded, because a perk with an unreadable header is still what a
    /// runtime formula queries.
    public let data: PerkHeaderData?
    /// NNAM, the next rank of this perk. Null links decode to nil.
    public let nextPerk: FormID?
    public let effects: [PerkEffect]
    public let script: ScriptData
    public let skipped: PerkTally

    /// The rank count the record declares, defaulting to one when DATA did not
    /// decode. Not the number of ranks the perk actually has: that is the
    /// length of its NNAM chain, which `PerkStore.rankChain(from:)` walks.
    public var declaredRankCount: UInt8 {
        max(data?.rankCount ?? 1, 1)
    }

    public var isPlayable: Bool {
        data?.isPlayable ?? false
    }

    /// Every effect that hooks an entry point, in record order.
    public var entryPointEffects: [PerkEffect] {
        effects.filter { $0.entryPoint != nil }
    }

    public init(record: ESMRecord, localized: Bool) throws {
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
