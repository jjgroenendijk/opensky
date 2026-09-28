// AVIF, the Actor Value Information record: the name, abbreviation and
// description of one actor value, plus — for the eighteen skills — the
// experience parameters that drive advancement and the perk-tree node graph.
//
// References: UESP "Skyrim Mod:Mod File Format/AVIF"
//   https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/AVIF
// Cross-checked against xEdit dev-4.1.6 Core/wbDefinitionsTES5.pas,
//   `wbRecord(AVIF, 'Actor Value Information', [...])`: EDID, FULL, required
//   DESC, ICON, ANAM, the CNAM skill-category enum, the four-float AVSK struct
//   and the `wbRArray('Perk Tree', ...)` decoded in
//   ActorValueInformationPerkTree.swift.
// Layout and real-install evidence: docs/formats/actor-value-information.md.

import Foundation

nonisolated enum ActorValueInformationSkipKind: Hashable {
    case unknownField(FourCC)
    case malformedField(FourCC)
    /// A perk-tree node that reached its end without one of the fields xEdit
    /// marks required. The node is still kept, with zeroes standing in.
    case incompletePerkTreeNode
}

nonisolated struct ActorValueInformationTally: Equatable {
    private(set) var counts: [ActorValueInformationSkipKind: Int] = [:]

    var total: Int {
        counts.values.reduce(0, +)
    }

    mutating func note(_ kind: ActorValueInformationSkipKind) {
        counts[kind, default: 0] += 1
    }
}

/// CNAM at record level: which of the three menu columns a skill's perk tree
/// is drawn under.
///
/// UESP records that on a record with no perk tree the same field carries
/// something else ("large 4byte info"), so the raw word is kept on the record
/// and this enum is derived from it. An out-of-range word is `unknown` rather
/// than a decode failure.
nonisolated enum ActorValueSkillCategory: Equatable, CustomStringConvertible {
    case none
    case combat
    case magic
    case stealth
    case unknown(raw: UInt32)

    init(rawValue: UInt32) {
        switch rawValue {
        case 0: self = .none
        case 1: self = .combat
        case 2: self = .magic
        case 3: self = .stealth
        default: self = .unknown(raw: rawValue)
        }
    }

    var description: String {
        switch self {
        case .none: "none"
        case .combat: "combat"
        case .magic: "magic"
        case .stealth: "stealth"
        case let .unknown(raw): "unknown (\(raw))"
        }
    }
}

/// AVSK, the four floats that turn skill use into skill level.
///
/// The two sources disagree on the name of the second float: UESP calls it
/// "Skill Use Offset" and xEdit "Skill Offset Mult". Nothing here depends on
/// the reading, so the field is stored under UESP's name and the disagreement
/// is left visible instead of being resolved by guesswork. Consuming these for
/// experience gain is issue 20.5.
nonisolated struct SkillUseParameters: Equatable {
    static let byteCount = 16

    let useMultiplier: Float
    let useOffset: Float
    let improveMultiplier: Float
    let improveOffset: Float

    init(
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

    init(field: ESMField) throws {
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

nonisolated struct ActorValueInformation: Equatable {
    let formID: FormID
    let editorID: String?
    let name: LString?
    let description: LString?
    /// ANAM. UESP notes it is only authored on a couple of records, so nil is
    /// the normal answer rather than a miss.
    let abbreviation: String?
    let iconPath: String?
    /// CNAM verbatim, or nil when the record has none.
    let categoryRaw: UInt32?
    let skillUse: SkillUseParameters?
    let perkTree: [PerkTreeNode]
    let skipped: ActorValueInformationTally

    var skillCategory: ActorValueSkillCategory? {
        categoryRaw.map(ActorValueSkillCategory.init(rawValue:))
    }

    /// Whether this record carries a tree to spend perk points in, together
    /// with the advancement parameters that go beside one.
    ///
    /// This is not the same question as "is this one of the eighteen skills".
    /// Dawnguard hangs the vampire and werewolf trees off actor values that
    /// are not skills and that the vanilla name table does not carry, so a
    /// caller that means the skills has to join the index and ask
    /// `ActorValueIdentity.isSkill(index:)` — which is what the store's
    /// `skills` does.
    var hasPerkTree: Bool {
        skillUse != nil && !perkTree.isEmpty
    }

    /// The vanilla actor-value index this record describes, or nil when no
    /// vanilla name matches it.
    ///
    /// The join is by name, because AVIF carries no index of its own. Editor
    /// IDs are tried first and the localizable FULL name last: a FULL that
    /// lives in a string table decodes to an ID rather than text, so it cannot
    /// be the primary key. `ActorValueIdentity.index(recordName:)` compares
    /// with punctuation dropped and case folded, which is what makes the
    /// table's `One-Handed` and an editor ID's `OneHanded` one name, and it
    /// carries the three legacy spellings vanilla editor ids use.
    var vanillaActorValueIndex: Int32? {
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

    init(record: ESMRecord, localized: Bool) throws {
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

/// Field-order-sensitive accumulator.
///
/// AVIF is the first record OpenSky decodes where one field tag means two
/// different things depending on position: CNAM before the first PNAM is the
/// record's skill category, and every CNAM after one is a connection line
/// inside the perk-tree node that PNAM opened. Tracking the open node is
/// therefore not an optimization, it is the disambiguation.
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
