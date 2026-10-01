// AVIF perk-tree section: the repeated node group of a skill's AVIF record.
// Layout and sources: docs/formats/actor-value-information.md.

import Foundation
import OpenSkyFormatsCore

/// Where one perk box sits in the skill's perk grid.
///
/// XNAM and YNAM place the box on the integer grid; HNAM and VNAM offset it
/// within that cell, which is what lets the vanilla trees draw boxes that do
/// not line up on a strict lattice.
nonisolated public struct PerkGridPosition: Equatable, Sendable {
    public let column: UInt32
    public let row: UInt32
    public let horizontal: Float
    public let vertical: Float
}

/// One box in a skill's perk tree. `perk` stays a raw plugin-relative `FormID`,
/// because resolving it needs a load order.
nonisolated public struct PerkTreeNode: Equatable, Sendable {
    /// PNAM, the PERK this box grants, or nil for the NULL link the first node
    /// of a tree carries.
    public let perk: FormID?
    /// FNAM verbatim. xEdit types it as a boolean ("Parent Required") while
    /// UESP records that the first node of a tree usually carries a very large
    /// value, so the raw word is kept and the boolean is derived from it rather
    /// than the other way round.
    public let parentRequiredRaw: UInt32
    public let position: PerkGridPosition
    /// SNAM, the AVIF this node belongs to — normally the record carrying it.
    public let associatedSkill: FormID?
    /// Every CNAM in the node: the INAM of a box this one draws a line to.
    /// Zero, one or many, per the spec's repeated-field array.
    public let connections: [UInt32]
    /// INAM, this box's identity inside the tree. Unique but not sequential,
    /// which is why connections address it instead of an array position.
    public let index: UInt32

    public var parentRequired: Bool {
        parentRequiredRaw != 0
    }

    /// The tree's entry node: no perk and index 0, the pair xEdit tests for
    /// when it hides the FNAM value.
    public var isRoot: Bool {
        perk == nil && index == 0
    }
}

/// Accumulates one node's fields as they stream past, because AVIF nodes are a
/// flat field run delimited by PNAM rather than a sized struct.
///
/// Every field is optional while collecting: a record that omits one is a mod
/// quirk to be tallied, not a parse that should throw away the whole record.
nonisolated public struct PerkTreeNodeBuilder: Sendable {
    public var perk: FormID?
    public var parentRequiredRaw: UInt32?
    public var column: UInt32?
    public var row: UInt32?
    public var horizontal: Float?
    public var vertical: Float?
    public var associatedSkill: FormID?
    public var connections: [UInt32] = []
    public var index: UInt32?

    /// Whether every field xEdit marks required was present. A false answer is
    /// reported through the record's tally; the node is still built.
    public var isComplete: Bool {
        parentRequiredRaw != nil && column != nil && row != nil
            && horizontal != nil && vertical != nil && index != nil
    }

    /// The node as decoded, with a missing numeric field standing in as zero
    /// so a quirky record still contributes a placed box.
    public func build() -> PerkTreeNode {
        PerkTreeNode(
            perk: perk,
            parentRequiredRaw: parentRequiredRaw ?? 0,
            position: PerkGridPosition(
                column: column ?? 0,
                row: row ?? 0,
                horizontal: horizontal ?? 0,
                vertical: vertical ?? 0
            ),
            associatedSkill: associatedSkill,
            connections: connections,
            index: index ?? 0
        )
    }

    /// Consumes one field of the node run. Returns false for a field type that
    /// is not part of a node, which is what tells the record decoder the run
    /// has ended.
    public mutating func decode(_ field: ESMField) throws -> Bool {
        switch field.type {
        case "PNAM": perk = try ActorValueInformationFieldReader.link(field)
        case "FNAM": parentRequiredRaw = try ActorValueInformationFieldReader.word(field)
        case "XNAM": column = try ActorValueInformationFieldReader.word(field)
        case "YNAM": row = try ActorValueInformationFieldReader.word(field)
        case "HNAM": horizontal = try ActorValueInformationFieldReader.float(field)
        case "VNAM": vertical = try ActorValueInformationFieldReader.float(field)
        case "SNAM": associatedSkill = try ActorValueInformationFieldReader.link(field)
        case "CNAM": try connections.append(ActorValueInformationFieldReader.word(field))
        case "INAM": index = try ActorValueInformationFieldReader.word(field)
        default: return false
        }
        return true
    }
}

/// The four fixed-width reads AVIF fields need, each checking its own length so
/// a truncated field throws instead of reading past the end.
nonisolated public enum ActorValueInformationFieldReader: Sendable {
    public static func word(_ field: ESMField) throws -> UInt32 {
        var reader = try BinaryReader(sized(field, bytes: 4))
        return try reader.readUInt32()
    }

    public static func float(_ field: ESMField) throws -> Float {
        var reader = try BinaryReader(sized(field, bytes: 4))
        return try reader.readFloat32()
    }

    public static func link(_ field: ESMField) throws -> FormID? {
        let id = try FormID(word(field))
        return id.isNull ? nil : id
    }

    public static func zstring(_ field: ESMField) throws -> String {
        var reader = BinaryReader(field.data)
        return try reader.readZString()
    }

    private static func sized(_ field: ESMField, bytes: Int) throws -> Data {
        guard field.data.count >= bytes else {
            throw ESMError.malformed(
                "AVIF \(field.type) has \(field.data.count) bytes, expected \(bytes)"
            )
        }
        return field.data
    }
}
