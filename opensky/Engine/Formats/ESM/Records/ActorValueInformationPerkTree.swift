// AVIF perk-tree section: the repeated node group that hangs off a skill's
// Actor Value Information record. Split out of ActorValueInformation.swift so
// both files stay inside the strict-lint file-length cap.
//
// References: UESP "Skyrim Mod:Mod File Format/AVIF", "Perk Sections"
//   https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/AVIF
// Cross-checked against xEdit dev-4.1.6 Core/wbDefinitionsTES5.pas,
//   `wbRecord(AVIF, ...)` -> `wbRArray('Perk Tree', wbRStruct('Node', [...]))`,
//   which orders the node as PNAM, FNAM, XNAM, YNAM, HNAM, VNAM, SNAM, then a
//   `wbRArray('Connections', wbInteger(CNAM, 'Line to Index', itU32))` and INAM.
// Layout and real-install evidence: docs/formats/actor-value-information.md.

import Foundation

/// Where one perk box sits in the skill's perk grid.
///
/// XNAM and YNAM place the box on the integer grid; HNAM and VNAM offset it
/// within that cell, which is what lets the vanilla trees draw boxes that do
/// not line up on a strict lattice.
nonisolated struct PerkGridPosition: Equatable {
    let column: UInt32
    let row: UInt32
    let horizontal: Float
    let vertical: Float
}

/// One box in a skill's perk tree.
///
/// The `perk` link stays a raw plugin-relative `FormID` here: resolving it to
/// a PERK record needs a load order and a PERK decoder, which is issue 20.2.
nonisolated struct PerkTreeNode: Equatable {
    /// PNAM, the PERK this box grants, or nil for the NULL link the first node
    /// of a tree carries.
    let perk: FormID?
    /// FNAM verbatim. xEdit types it as a boolean ("Parent Required") while
    /// UESP records that the first node of a tree usually carries a very large
    /// value, so the raw word is kept and the boolean is derived from it rather
    /// than the other way round.
    let parentRequiredRaw: UInt32
    let position: PerkGridPosition
    /// SNAM, the AVIF this node belongs to — normally the record carrying it.
    let associatedSkill: FormID?
    /// Every CNAM in the node: the INAM of a box this one draws a line to.
    /// Zero, one or many, per the spec's repeated-field array.
    let connections: [UInt32]
    /// INAM, this box's identity inside the tree. Unique but not sequential,
    /// which is why connections address it instead of an array position.
    let index: UInt32

    var parentRequired: Bool {
        parentRequiredRaw != 0
    }

    /// The tree's entry node: no perk and index 0, the pair xEdit tests for
    /// when it hides the FNAM value.
    var isRoot: Bool {
        perk == nil && index == 0
    }
}

/// Accumulates one node's fields as they stream past, because AVIF nodes are a
/// flat field run delimited by PNAM rather than a sized struct.
///
/// Every field is optional while collecting: a record that omits one is a mod
/// quirk to be tallied, not a parse that should throw away the whole record.
nonisolated struct PerkTreeNodeBuilder {
    var perk: FormID?
    var parentRequiredRaw: UInt32?
    var column: UInt32?
    var row: UInt32?
    var horizontal: Float?
    var vertical: Float?
    var associatedSkill: FormID?
    var connections: [UInt32] = []
    var index: UInt32?

    /// Whether every field xEdit marks required was present. A false answer is
    /// reported through the record's tally; the node is still built.
    var isComplete: Bool {
        parentRequiredRaw != nil && column != nil && row != nil
            && horizontal != nil && vertical != nil && index != nil
    }

    /// The node as decoded, with a missing numeric field standing in as zero
    /// so a quirky record still contributes a placed box.
    func build() -> PerkTreeNode {
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
    mutating func decode(_ field: ESMField) throws -> Bool {
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
nonisolated enum ActorValueInformationFieldReader {
    static func word(_ field: ESMField) throws -> UInt32 {
        var reader = try BinaryReader(sized(field, bytes: 4))
        return try reader.readUInt32()
    }

    static func float(_ field: ESMField) throws -> Float {
        var reader = try BinaryReader(sized(field, bytes: 4))
        return try reader.readFloat32()
    }

    static func link(_ field: ESMField) throws -> FormID? {
        let id = try FormID(word(field))
        return id.isNull ? nil : id
    }

    static func zstring(_ field: ESMField) throws -> String {
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
