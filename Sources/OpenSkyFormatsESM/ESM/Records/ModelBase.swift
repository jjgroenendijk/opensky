// One decoder for the base records that are a named model (MSTT, TREE, FLOR,
// FURN, ACTI, TACT, CONT, DOOR, and the carryable items), plus their sound
// links. A DOOR's teleport data lives on the placed REFR, not here.
// Layout and sources: docs/formats/world-records.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct ModelBase: Sendable {
    /// Record types this decoder accepts. ARMO is not one: its world model is
    /// MOD2/MOD3 and its body pieces come from ARMA, so a dropped armor piece
    /// is not drawn yet, and the take path reports that.
    public static let supportedTypes: Set<FourCC> = [
        "MSTT", "TREE", "FLOR", "FURN", "ACTI", "TACT", "CONT", "DOOR",
        "MISC", "WEAP", "AMMO", "ALCH", "INGR", "BOOK", "KEYM", "SLGM", "APPA"
    ]

    /// The subset of `supportedTypes` whose references are loose world items:
    /// activating one takes it into an inventory. Read by
    /// `CellSceneBuilder.interactionAction(for:)` and by the take path, so both
    /// answer from one list.
    public static let itemTypes: Set<FourCC> = [
        "MISC", "WEAP", "AMMO", "ALCH", "INGR", "BOOK", "KEYM", "SLGM", "APPA"
    ]

    /// Sound links of an activator, door, or container, grouped by meaning.
    /// Each targets a SNDR. Field names differ per record: CONT closes with
    /// QNAM, not ANAM. Table: docs/formats/world-records.md.
    public struct Sounds: Equatable, Sendable {
        /// One-shot on use-key activation. DOOR.SNAM, ACTI.VNAM, CONT.SNAM.
        public let activation: FormID?
        /// One-shot on close.
        /// DOOR.ANAM, CONT.QNAM.
        public let close: FormID?
        /// Continuous positional loop while in range. DOOR.BNAM, ACTI.SNAM, TACT.SNAM.
        public let loop: FormID?
    }

    public let formID: FormID
    public let recordType: FourCC
    public let editorID: String?
    /// FULL — in-game display name; localized plugins store a string-table ID.
    public let name: LString?
    /// ACTI and FLOR RNAM — custom activation verb such as "Mine" or "Place".
    public let activateTextOverride: LString?
    /// Record-specific flags can suppress manual use-key activation.
    public let allowsManualInteraction: Bool
    /// MODL — mesh path relative to Data/ (e.g. "meshes\\trees\\treepineforest01.nif").
    /// Nil for bases with no model (rare outside markers).
    public let modelPath: String?
    /// Sound links for activator/door/container bases; nil when the record
    /// carries none of the decoded sound fields.
    public let sounds: Sounds?
    /// VMAD — Papyrus scripts attached to this activator-like base record.
    public let scriptData: ScriptData
    /// KSIZ + KWDA. A FURN crafting station names its workbench keyword here.
    public let keywords: KeywordList
    /// ACTI and FURN KNAM.
    public let interactionKeyword: FormID?
    /// FURN WBDT. Nil on other types and on furniture without the field.
    public let workbench: Workbench?
    /// FLOR and TREE produce. Nil when the record carries none of its fields.
    public let produce: HarvestProduce?
    /// TACT VNAM, a VTYP.
    public let voiceType: FormID?
    /// Fields this decoder does not read, and fields too short to read.
    public let skipped: ItemFieldTally

    public init(record: ESMRecord, localized: Bool = false) throws {
        guard Self.supportedTypes.contains(record.type) else {
            let accepted = Self.supportedTypes.map(\.description).sorted().joined(separator: "/")
            throw ESMError.malformed(
                "expected one of \(accepted), got \(record.type)"
            )
        }
        formID = FormID(record.formID)
        recordType = record.type

        var fields = ModelBaseFields(ownerType: record.type)
        var skipped = ItemFieldTally()
        for field in try record.fields() {
            do {
                if try !fields.decode(field: field, recordType: record.type, localized: localized) {
                    skipped.note(.unknownField(field.type))
                }
            } catch {
                skipped.note(.malformedField(field.type))
            }
        }
        editorID = fields.editorID
        name = fields.name
        activateTextOverride = fields.activateTextOverride
        // xEdit dev-4.1.6: ACTI header bit 20 is Ignore Object
        // Interaction; DOOR FNAM bit 1 is Automatic; FURN MNAM bit 25
        // disables activation.
        allowsManualInteraction = !(record.type == "ACTI"
            && record.flags.rawValue & (1 << 20) != 0)
            && !(record.type == "DOOR" && fields.doorFlags & 0x02 != 0)
            && !(record.type == "FURN" && fields.furnitureMarkers & 0x0200_0000 != 0)
        modelPath = fields.modelPath
        sounds = Self.buildSounds(
            activation: fields.activationSound,
            close: fields.closeSound,
            loop: fields.loopSound
        )
        scriptData = fields.scriptData
        keywords = fields.world.keywords
        interactionKeyword = fields.world.interactionKeyword
        workbench = fields.world.workbench
        produce = fields.world.produce
        voiceType = fields.world.voiceType
        self.skipped = skipped
    }

    /// Mutable accumulator for the field loop; keeps the switch out of init so
    /// the file stays inside the lint complexity limit.
    private struct ModelBaseFields {
        var editorID: String?
        var name: LString?
        var activateTextOverride: LString?
        var modelPath: String?
        var doorFlags: UInt8 = 0
        var furnitureMarkers: UInt32 = 0
        var activationSound: FormID?
        var closeSound: FormID?
        var loopSound: FormID?
        var scriptData: ScriptData
        var world = ModelBaseWorldFields()

        init(ownerType: FourCC) {
            scriptData = ScriptData(ownerType: ownerType)
        }

        /// Returns false when no part of this decoder reads `field`.
        mutating func decode(
            field: ESMField, recordType: FourCC, localized: Bool
        ) throws -> Bool {
            guard try !scriptData.decode(field: field) else { return true }
            guard try !world.decode(field: field, recordType: recordType) else { return true }
            var reader = BinaryReader(field.data)
            switch field.type {
            case "EDID":
                editorID = try reader.readZString()
            case "FULL":
                name = try LString(field: field, localized: localized)
            case "MODL":
                modelPath = try reader.readZString()
            case "RNAM" where recordType == "ACTI" || recordType == "FLOR":
                activateTextOverride = try LString(field: field, localized: localized)
            case "FNAM" where recordType == "DOOR":
                doorFlags = try reader.readUInt8()
            case "MNAM" where recordType == "FURN":
                furnitureMarkers = try reader.readUInt32()
            default:
                // Sound links live in a separate helper to keep this decode
                // switch below the strict-lint cyclomatic-complexity cap.
                return try decodeSoundField(
                    field: field, recordType: recordType, reader: &reader
                )
            }
            return true
        }

        private mutating func decodeSoundField(
            field: ESMField, recordType: FourCC, reader: inout BinaryReader
        ) throws -> Bool {
            // Sound links — see Sounds doc for the per-type field authority.
            // All three are 4-byte optional FormIDs into SNDR (or SOUN legacy
            // marker; the director resolves that hop).
            switch (field.type, recordType) {
            case ("SNAM", "DOOR"):
                activationSound = try Self.readOptionalFormID(&reader, size: field.data.count)
            case ("ANAM", "DOOR"):
                closeSound = try Self.readOptionalFormID(&reader, size: field.data.count)
            case ("BNAM", "DOOR"):
                loopSound = try Self.readOptionalFormID(&reader, size: field.data.count)
            case ("SNAM", "ACTI"), ("SNAM", "TACT"):
                loopSound = try Self.readOptionalFormID(&reader, size: field.data.count)
            case ("VNAM", "ACTI"):
                activationSound = try Self.readOptionalFormID(&reader, size: field.data.count)
            case ("SNAM", "CONT"):
                activationSound = try Self.readOptionalFormID(&reader, size: field.data.count)
            case ("QNAM", "CONT"):
                closeSound = try Self.readOptionalFormID(&reader, size: field.data.count)
            default:
                return false
            }
            return true
        }

        private static func readOptionalFormID(
            _ reader: inout BinaryReader,
            size: Int
        ) throws -> FormID? {
            guard size == 4 else { return nil }
            let formID = try FormID(reader.readUInt32())
            return formID.isNull ? nil : formID
        }
    }

    private static func buildSounds(
        activation: FormID?, close: FormID?, loop: FormID?
    ) -> Sounds? {
        guard activation != nil || close != nil || loop != nil else { return nil }
        return Sounds(activation: activation, close: close, loop: loop)
    }
}
