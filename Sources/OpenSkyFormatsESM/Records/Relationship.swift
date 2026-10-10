// RELA relationship: a directed pair of NPC_ bases, their rank, a secret flag,
// and an optional ASTP link. Links and raw values only.
// Layout and sources: docs/formats/relationships.md.

import Foundation
import OpenSkyFormatsCore

/// DATA offset 8, uint16. The nine values the Creation Kit names, in the order
/// both sources list them.
///
/// The stored value counts up from the friendliest, while the value
/// `GetRelationshipRank` returns counts down from +4 to -4 — `signedRank`
/// carries that conversion so a caller never re-derives it from the raw word.
nonisolated public enum RelationshipRank: Equatable, CustomStringConvertible, Sendable {
    case lover
    case ally
    case confidant
    case friend
    case acquaintance
    case rival
    case foe
    case enemy
    case archnemesis
    /// A value outside 0...8. Kept rather than clamped: a mod may author one,
    /// and a clamp would silently turn it into a real rank.
    case unknown(raw: UInt16)

    public init(rawValue: UInt16) {
        switch rawValue {
        case 0: self = .lover
        case 1: self = .ally
        case 2: self = .confidant
        case 3: self = .friend
        case 4: self = .acquaintance
        case 5: self = .rival
        case 6: self = .foe
        case 7: self = .enemy
        case 8: self = .archnemesis
        default: self = .unknown(raw: rawValue)
        }
    }

    public var rawValue: UInt16 {
        switch self {
        case .lover: 0
        case .ally: 1
        case .confidant: 2
        case .friend: 3
        case .acquaintance: 4
        case .rival: 5
        case .foe: 6
        case .enemy: 7
        case .archnemesis: 8
        case let .unknown(raw): raw
        }
    }

    /// The rank a signed `GetRelationshipRank` number names, or nil for a
    /// number outside the -4...4 the Creation Kit lists as acceptable
    /// (<https://ck.uesp.net/wiki/SetRelationshipRank_-_Actor>). The inverse of
    /// `signedRank`, and what turns a scripted rank back into a record rank so
    /// the reaction grouping can be applied to it.
    public init?(signedRank: Int) {
        guard (-4 ... 4).contains(signedRank) else { return nil }
        self.init(rawValue: UInt16(4 - signedRank))
    }

    /// The `GetRelationshipRank` value: +4 for a lover down to -4 for an
    /// archnemesis, and nil for a raw value the spec does not name.
    public var signedRank: Int? {
        switch self {
        case .unknown: nil
        default: 4 - Int(rawValue)
        }
    }

    public var description: String {
        switch self {
        case .lover: "lover"
        case .ally: "ally"
        case .confidant: "confidant"
        case .friend: "friend"
        case .acquaintance: "acquaintance"
        case .rival: "rival"
        case .foe: "foe"
        case .enemy: "enemy"
        case .archnemesis: "archnemesis"
        case let .unknown(raw): "unknown (\(raw))"
        }
    }
}

/// DATA offset 13, uint8. xEdit reads a byte here with `0x80` named Secret and
/// the other seven bits unnamed; UESP reads offsets 12...13 as one uint16 whose
/// only named bit is `0x8000`. Little-endian, those are the same bit, so this
/// takes the byte reading and keeps the byte at offset 12 verbatim.
nonisolated public struct RelationshipFlags: OptionSet, Equatable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let secret = RelationshipFlags(rawValue: 0x80)
}

/// The whole DATA struct, 16 bytes.
nonisolated public struct RelationshipData: Equatable, Sendable {
    public static let byteCount = 16

    /// Both links are `NPC_` or NULL. "Parent" and "child" are the record's own
    /// direction words and carry no biological meaning — the association type
    /// is what says whether the pair is a family, a courtship or a rivalry.
    public let parent: FormID?
    public let child: FormID?
    public let rank: RelationshipRank
    /// Offset 12, xEdit `wbByteArray('Unknown', 1)`. Kept verbatim because a
    /// nonzero byte there is the observation that would separate the two
    /// readings of the flag word.
    public let unknown: UInt8
    public let flags: RelationshipFlags
    /// ASTP or NULL, left unresolved here: joining it is `RelationshipStore`'s.
    public let associationType: FormID?

    public init(field: ESMField) throws {
        guard field.data.count >= Self.byteCount else {
            throw ESMError.malformed(
                "RELA DATA has \(field.data.count) bytes, expected at least \(Self.byteCount)"
            )
        }
        var reader = BinaryReader(field.data)
        parent = try Self.link(reader.readUInt32())
        child = try Self.link(reader.readUInt32())
        rank = try RelationshipRank(rawValue: reader.readUInt16())
        unknown = try reader.readUInt8()
        flags = try RelationshipFlags(rawValue: reader.readUInt8())
        associationType = try Self.link(reader.readUInt32())
    }

    /// A null link is absent, matching how the other reference records read a
    /// zero FormID.
    private static func link(_ raw: UInt32) -> FormID? {
        let id = FormID(raw)
        return id.isNull ? nil : id
    }
}

nonisolated public struct Relationship: Equatable, Sendable {
    /// xEdit also names bit 6 of the RELA *record header* flags "Secret"
    /// (`wbRecord(RELA, 'Relationship', wbFlags(wbFlagsList([6, 'Secret'])), ...)`),
    /// which UESP does not mention at all. Neither source says which of the two
    /// the game reads, so both are decoded and the real-data suite reports how
    /// often they disagree.
    public static let secretHeaderFlag: UInt32 = 1 << 6

    public let formID: FormID
    public let editorID: String?
    /// Nil when the record carries no DATA or a truncated one. A relationship
    /// without it names no pair, so the store drops it rather than inventing
    /// a parent; the tally records why.
    public let data: RelationshipData?
    /// Record header flag bit 6 — see `secretHeaderFlag`.
    public let headerSecret: Bool
    public let skipped: ReferenceRecordTally

    public var parent: FormID? {
        data?.parent
    }

    public var child: FormID? {
        data?.child
    }

    public var rank: RelationshipRank? {
        data?.rank
    }

    public var associationType: FormID? {
        data?.associationType
    }

    public var isSecret: Bool {
        data?.flags.contains(.secret) ?? false
    }

    public init(record: ESMRecord) throws {
        guard record.type == "RELA" else {
            throw ESMError.malformed("expected RELA record, got \(record.type)")
        }
        formID = FormID(record.formID)
        headerSecret = record.flags.rawValue & Self.secretHeaderFlag != 0
        var editorID: String?
        var data: RelationshipData?
        var tally = ReferenceRecordTally()
        for field in try record.fields() {
            do {
                var reader = BinaryReader(field.data)
                switch field.type {
                case "EDID": editorID = try reader.readZString()
                case "DATA": data = try RelationshipData(field: field)
                default: tally.note(.unknownField(field.type))
                }
            } catch {
                tally.note(.malformedField(field.type))
            }
        }
        self.editorID = editorID
        self.data = data
        skipped = tally
    }
}
