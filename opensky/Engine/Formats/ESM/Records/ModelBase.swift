// MSTT/TREE/FURN/ACTI/CONT/DOOR records decoded into engine types: same
// EDID + FULL + MODL shape — a named model a placed reference resolves to.
// One shared decoder rather than six near-identical structs; type-specific
// fields stay unread until a milestone needs them.
// DOOR joins for M3.6: its MODL renders through the same static-model path;
// teleport data lives on placed REFR XTEL, not the base.
// M9.2.2 adds sound links for DOOR/ACTI/CONT (issue #155).
//
// Reference: UESP "Skyrim Mod:Mod File Format" per-record pages document
// the type layouts below. xEdit dev-4.1.6 wbDefinitionsTES5.pas is the
// cross-type authority for FULL, RNAM, FNAM, MNAM, suppression flags, and
// the SNDR-link sound fields:
// https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsTES5.pas
//   /MSTT  https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/MSTT
//   /TREE  https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/TREE
//   /FURN  https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/FURN
//   /ACTI  https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/ACTI
//   /CONT  https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/CONT
//   /DOOR  https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/DOOR
// Layout documented in docs/formats/records.md.

import Foundation

nonisolated struct ModelBase {
    /// Record types this decoder accepts — all carry EDID + MODL where STAT
    /// does. CellSceneBuilder indexes each of these top groups separately.
    ///
    /// The six carryable families joined for M12.1.3 (issue #177), which is
    /// what makes a loose item reference resolve a model, a collision shape and
    /// a `.take` interaction instead of counting as an unsupported base. Their
    /// world model is a plain MODL exactly as MSTT's is, so nothing about the
    /// decode changes; only the accepted set does.
    ///
    /// ARMO is deliberately absent even though it is a carryable family. Its
    /// world model is MOD2/MOD3 and body pieces resolve through ARMA addons
    /// rather than through a single MODL, so it needs the arbitration issue
    /// #178 owns. A dropped cuirass is therefore not yet drawable, which the
    /// take path reports rather than hides.
    static let supportedTypes: Set<FourCC> = [
        "MSTT", "TREE", "FURN", "ACTI", "CONT", "DOOR",
        "MISC", "WEAP", "AMMO", "ALCH", "INGR", "BOOK"
    ]

    /// The subset of `supportedTypes` whose references are loose world items:
    /// activating one takes it into an inventory. Read by
    /// `CellSceneBuilder.interactionAction(for:)` and by the take path, so both
    /// answer from one list.
    static let itemTypes: Set<FourCC> = [
        "MISC", "WEAP", "AMMO", "ALCH", "INGR", "BOOK"
    ]

    /// Sound links carried by an activator/door/container base. Each FormID
    /// targets a SNDR descriptor (a SOUN legacy marker resolves to one via
    /// SOUN.SDSC; the runtime resolves that hop through SoundRecordStore).
    /// Field-name -> meaning varies by record type; this struct groups by
    /// runtime semantics so the sound director reads one field per concept.
    ///
    /// xEdit dev-4.1.6 wbDefinitionsTES5.pas authorities:
    ///   DOOR SNAM/ANAM/BNAM at lines 4921-4923
    ///   ACTI SNAM/VNAM     at lines 3323-3324
    ///   CONT SNAM/QNAM     at lines 4519-4520  (QNAM, not ANAM — cross-record
    ///                                            trap; ANAM on CONT is a
    ///                                            different unused field)
    struct Sounds: Equatable {
        /// One-shot on use-key activation. DOOR.SNAM, ACTI.VNAM, CONT.SNAM.
        let activation: FormID?
        /// One-shot on close.
        /// DOOR.ANAM, CONT.QNAM.
        let close: FormID?
        /// Continuous positional loop while in range. DOOR.BNAM, ACTI.SNAM.
        let loop: FormID?
    }

    let formID: FormID
    let recordType: FourCC
    let editorID: String?
    /// FULL — in-game display name; localized plugins store a string-table ID.
    let name: LString?
    /// ACTI RNAM — custom activation verb such as "Mine" or "Place".
    let activateTextOverride: LString?
    /// Record-specific flags can suppress manual use-key activation.
    let allowsManualInteraction: Bool
    /// MODL — mesh path relative to Data/ (e.g. "meshes\\trees\\treepineforest01.nif").
    /// Nil for bases with no model (rare outside markers).
    let modelPath: String?
    /// Sound links for activator/door/container bases; nil when the record
    /// carries none of the decoded sound fields.
    let sounds: Sounds?
    /// VMAD — Papyrus scripts attached to this activator-like base record.
    let scriptData: ScriptData

    init(record: ESMRecord, localized: Bool = false) throws {
        guard Self.supportedTypes.contains(record.type) else {
            let accepted = Self.supportedTypes.map(\.description).sorted().joined(separator: "/")
            throw ESMError.malformed(
                "expected one of \(accepted), got \(record.type)"
            )
        }
        formID = FormID(record.formID)
        recordType = record.type

        var fields = ModelBaseFields(ownerType: record.type)
        for field in try record.fields() {
            try fields.decode(field: field, recordType: record.type, localized: localized)
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
    }

    /// Mutable accumulator for the field loop; keeps the switch (and its
    /// cyclomatic complexity) out of init so the file stays inside strict-lint
    /// limits once the M9.2.2 sound fields landed.
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

        init(ownerType: FourCC) {
            scriptData = ScriptData(ownerType: ownerType)
        }

        mutating func decode(
            field: ESMField, recordType: FourCC, localized: Bool
        ) throws {
            guard try !scriptData.decode(field: field) else { return }
            var reader = BinaryReader(field.data)
            switch field.type {
            case "EDID":
                editorID = try reader.readZString()
            case "FULL":
                name = try LString(field: field, localized: localized)
            case "MODL":
                modelPath = try reader.readZString()
            case "RNAM" where recordType == "ACTI":
                activateTextOverride = try LString(field: field, localized: localized)
            case "FNAM" where recordType == "DOOR":
                doorFlags = try reader.readUInt8()
            case "MNAM" where recordType == "FURN":
                furnitureMarkers = try reader.readUInt32()
            default:
                // Sound links live in a separate helper to keep this decode
                // switch below the strict-lint cyclomatic-complexity cap.
                try decodeSoundField(
                    field: field, recordType: recordType, reader: &reader
                )
            }
        }

        private mutating func decodeSoundField(
            field: ESMField, recordType: FourCC, reader: inout BinaryReader
        ) throws {
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
            case ("SNAM", "ACTI"):
                loopSound = try Self.readOptionalFormID(&reader, size: field.data.count)
            case ("VNAM", "ACTI"):
                activationSound = try Self.readOptionalFormID(&reader, size: field.data.count)
            case ("SNAM", "CONT"):
                activationSound = try Self.readOptionalFormID(&reader, size: field.data.count)
            case ("QNAM", "CONT"):
                closeSound = try Self.readOptionalFormID(&reader, size: field.data.count)
            default:
                break
            }
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
