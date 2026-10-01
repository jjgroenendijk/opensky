// AVIF: the name and description of one actor value, plus, for the skills, the
// experience parameters and the perk-tree node graph.
// Sources: UESP "Skyrim Mod:Mod File Format/AVIF" and xEdit wbDefinitionsTES5.pas.
// Layout: docs/formats/actor-value-information.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public enum ActorValueInformationSkipKind: Hashable, Sendable {
    case unknownField(FourCC)
    case malformedField(FourCC)
    /// A perk-tree node that reached its end without one of the fields xEdit
    /// marks required. The node is still kept, with zeroes standing in.
    case incompletePerkTreeNode
}

public typealias ActorValueInformationTally = SkipTally<ActorValueInformationSkipKind>

/// CNAM at record level: the menu column a skill's perk tree is drawn under.
/// On a record with no perk tree the field means something else, so the raw word
/// stays on the record and an out-of-range word reads as `unknown`.
nonisolated public enum ActorValueSkillCategory: Equatable, CustomStringConvertible, Sendable {
    case none
    case combat
    case magic
    case stealth
    case unknown(raw: UInt32)

    public init(rawValue: UInt32) {
        switch rawValue {
        case 0: self = .none
        case 1: self = .combat
        case 2: self = .magic
        case 3: self = .stealth
        default: self = .unknown(raw: rawValue)
        }
    }

    public var description: String {
        switch self {
        case .none: "none"
        case .combat: "combat"
        case .magic: "magic"
        case .stealth: "stealth"
        case let .unknown(raw): "unknown (\(raw))"
        }
    }
}

/// AVSK, the four floats that turn skill use into skill level. UESP names the
/// second float "Skill Use Offset", xEdit "Skill Offset Mult"; the UESP name is kept.
nonisolated public struct SkillUseParameters: Equatable, Sendable {
    public static let byteCount = 16

    public let useMultiplier: Float
    public let useOffset: Float
    public let improveMultiplier: Float
    public let improveOffset: Float

    public init(
        useMultiplier: Float,
        useOffset: Float,
        improveMultiplier: Float,
        improveOffset: Float
    ) {
        self.useMultiplier = useMultiplier
        self.useOffset = useOffset
        self.improveMultiplier = improveMultiplier
        self.improveOffset = improveOffset
    }

    public init(field: ESMField) throws {
        guard field.data.count == Self.byteCount else {
            throw ESMError.malformed(
                "AVIF AVSK has \(field.data.count) bytes, expected exactly \(Self.byteCount)"
            )
        }
        var reader = BinaryReader(field.data)
        useMultiplier = try reader.readFloat32()
        useOffset = try reader.readFloat32()
        improveMultiplier = try reader.readFloat32()
        improveOffset = try reader.readFloat32()
    }
}

nonisolated public struct ActorValueInformation: Equatable, Sendable {
    public let formID: FormID
    public let editorID: String?
    public let name: LString?
    public let description: LString?
    /// ANAM. UESP notes it is only authored on a couple of records, so nil is
    /// the normal answer rather than a miss.
    public let abbreviation: String?
    public let iconPath: String?
    /// CNAM verbatim, or nil when the record has none.
    public let categoryRaw: UInt32?
    public let skillUse: SkillUseParameters?
    public let perkTree: [PerkTreeNode]
    public let skipped: ActorValueInformationTally

    public var skillCategory: ActorValueSkillCategory? {
        categoryRaw.map(ActorValueSkillCategory.init(rawValue:))
    }

    /// Whether this record has a perk tree and its advancement parameters.
    /// Dawnguard trees hang off values that are not skills, so to ask "is this a
    /// skill" use `ActorValueIdentity.isSkill(index:)`, as the store's `skills` does.
    public var hasPerkTree: Bool {
        skillUse != nil && !perkTree.isEmpty
    }

    /// The vanilla actor-value index, joined by name because AVIF has no index.
    /// Editor IDs come first: a localized FULL decodes to a string ID, not text.
    /// `ActorValueIdentity.index(recordName:)` ignores case and punctuation.
    public var vanillaActorValueIndex: Int32? {
        if let editorID {
            if let index = ActorValueIdentity.index(recordName: editorID) {
                return index
            }
            // Vanilla prefixes most of these editor IDs with `AV`
            // (`AVOneHanded`), which no entry in the name table carries.
            if
                editorID.count > 2, editorID.hasPrefix("AV"),
                let index = ActorValueIdentity.index(recordName: String(editorID.dropFirst(2)))
            {
                return index
            }
        }
        if case let .inline(text) = name {
            return ActorValueIdentity.index(recordName: text)
        }
        return nil
    }

    public init(record: ESMRecord, localized: Bool) throws {
        guard record.type == "AVIF" else {
            throw ESMError.malformed("expected AVIF record, got \(record.type)")
        }
        var decoder = ActorValueInformationFields(localized: localized)
        for field in try record.fields() {
            decoder.decode(field)
        }
        decoder.finishPerkTreeNode()
        formID = FormID(record.formID)
        editorID = decoder.editorID
        name = decoder.name
        description = decoder.description
        abbreviation = decoder.abbreviation
        iconPath = decoder.iconPath
        categoryRaw = decoder.categoryRaw
        skillUse = decoder.skillUse
        perkTree = decoder.perkTree
        skipped = decoder.skipped
    }
}

/// Field-order-sensitive accumulator. A CNAM before the first PNAM is the skill
/// category; a CNAM after one is a connection line in the open perk-tree node.
nonisolated private struct ActorValueInformationFields {
    let localized: Bool
    var editorID: String?
    var name: LString?
    var description: LString?
    var abbreviation: String?
    var iconPath: String?
    var categoryRaw: UInt32?
    var skillUse: SkillUseParameters?
    var perkTree: [PerkTreeNode] = []
    var skipped = ActorValueInformationTally()

    private var node: PerkTreeNodeBuilder?

    init(localized: Bool) {
        self.localized = localized
    }

    mutating func decode(_ field: ESMField) {
        do {
            if field.type == "PNAM" {
                finishPerkTreeNode()
                node = PerkTreeNodeBuilder()
            }
            if node != nil, try decodeNodeField(field) {
                return
            }
            try decodeRecordField(field)
        } catch {
            skipped.note(.malformedField(field.type))
        }
    }

    /// Closes the node currently being collected, if any. Called on the next
    /// PNAM and once more after the last field.
    mutating func finishPerkTreeNode() {
        guard let node else { return }
        if !node.isComplete {
            skipped.note(.incompletePerkTreeNode)
        }
        perkTree.append(node.build())
        self.node = nil
    }

    private mutating func decodeNodeField(_ field: ESMField) throws -> Bool {
        guard var open = node else { return false }
        let consumed = try open.decode(field)
        node = open
        return consumed
    }

    private mutating func decodeRecordField(_ field: ESMField) throws {
        switch field.type {
        case "EDID": editorID = try ActorValueInformationFieldReader.zstring(field)
        case "FULL": name = try LString(field: field, localized: localized)
        case "DESC": description = try LString(field: field, localized: localized)
        case "ANAM": abbreviation = try ActorValueInformationFieldReader.zstring(field)
        case "ICON": iconPath = try ActorValueInformationFieldReader.zstring(field)
        case "CNAM": categoryRaw = try ActorValueInformationFieldReader.word(field)
        case "AVSK": skillUse = try SkillUseParameters(field: field)
        default: skipped.note(.unknownField(field.type))
        }
    }
}
