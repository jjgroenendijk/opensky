// REFR record decoded into engine types: base object FormID + placement.
// A REFR places one base record (STAT, TREE, DOOR, ...) at a world position.
// Per spec only NAME and DATA are required; everything else here is optional
// and most of the activation fields are still skipped.
//
// M12.1.1 adds the reference-level ownership subrecords so a container or a
// world item can say who it belongs to and how many of it there are:
//   XOWN 4 bytes  owning NPC_ or FACT
//   XRNK 4 bytes  int32 required rank, meaningful only for a faction owner
//   XCNT 4 bytes  int32 stack count for a placed inventory item
// xEdit models XOWN as a 12-byte struct for Fallout 4 and later only; in
// Skyrim it is a plain FormID (`wbOwnership`, wbDefinitionsCommon.pas line
// 8655), which is what this decodes.
//
// Reference: UESP "Skyrim Mod:Mod File Format/REFR"
//   https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/REFR
// XTEL and XLKR struct cross-check: xEdit dev-4.1.6 wbDefinitionsTES5.pas
//   https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsTES5.pas
// Layout documented in docs/formats/records.md.

import Foundation
import simd

nonisolated struct PlacedReference {
    /// DATA field: 24 bytes, positions in game units, rotations in radians
    /// (Skyrim world axes — see docs/decisions/coordinates.md).
    struct Placement: Equatable {
        let position: SIMD3<Float>
        let rotation: SIMD3<Float>
    }

    /// XTEL field: destination door reference + arrival transform + flags.
    /// xEdit names the FormID target "Door" but constrains it to REFR.
    struct TeleportDestination: Equatable {
        struct Flags: OptionSet, Equatable {
            let rawValue: UInt32

            static let noAlarm = Flags(rawValue: 0x0000_0001)
        }

        let door: FormID
        let placement: Placement
        let flags: Flags
    }

    /// XLKR field: one entry of the reference's linked-reference list.
    ///
    /// UESP REFR and xEdit both describe an 8-byte struct of `Keyword/Ref`
    /// followed by `Ref`; the keyword slot holds FormID 0 when the link is
    /// untagged, which decodes here as `keyword == nil`. xEdit marks the
    /// second member optional (`aOptionalFromElement: 1`), which is the
    /// 4-byte form, and it too decodes as an untagged link.
    ///
    /// Confirmed on real data by `PlacedReferenceLinkedRefRealDataTests`:
    /// Skyrim.esm's 12477 XLKR payloads are all exactly 8 bytes (12467) or
    /// exactly 4 (10), every non-null first FormID is a KYWD record and no
    /// second FormID ever is, so the order really is keyword then ref.
    ///
    /// Uncertainty: xEdit types slot 0 as `Keyword/Ref`, admitting a REFR
    /// there as well as a KYWD, because in the 4-byte form slot 0 *is* the
    /// ref. Skyrim.esm never puts a reference in slot 0 of an 8-byte payload,
    /// so OpenSky reads an 8-byte slot 0 as a keyword unconditionally. A mod
    /// that broke that would have its link read as tagged with a non-keyword.
    struct LinkedReference: Equatable {
        /// KYWD tagging the link (`LinkCarryStart`, `LinkCarryEnd`, ...).
        /// `nil` when the link carries no keyword.
        let keyword: FormID?
        /// The reference this REFR links to — a REFR/ACHR/PLYR in practice.
        let ref: FormID
    }

    let formID: FormID
    /// NAME — the base object this reference places.
    let base: FormID
    /// DATA placement as decoded. `var` because a cell build lays a runtime
    /// transform override over the record's value before it places anything
    /// (issue #160, `CellSceneBuilder.applyRuntimeState`); decoding itself
    /// never rewrites it.
    var placement: Placement
    /// XSCL — uniform scale, defaulting to 1 when the field is absent. `var`
    /// for the same runtime-override reason as `placement`.
    var scale: Float
    /// XTEL — present only on teleporting door references.
    let teleportDestination: TeleportDestination?
    /// XRDS — per-reference point-light radius override.
    let lightRadius: Float?
    /// XEMI — LIGH/REGN emittance override; LIGH handled by lighting pass.
    let emittance: FormID?
    /// XPRM — the primitive volume this reference encloses, nil when absent.
    /// Layout and decode policy live in `PlacedReferencePrimitive.swift`.
    let primitive: Primitive?
    /// XLKR — every linked reference, in file order. The subrecord repeats,
    /// so this is an array rather than an optional; it is empty when the
    /// reference links to nothing. Read it through
    /// `linkedReference(keyword:)` rather than by index.
    let linkedReferences: [LinkedReference]
    /// XOWN — the NPC_ or FACT that owns this reference; nil when unowned.
    /// Taking an owned item is theft, and an owned container is a crime scene.
    let owner: FormID?
    /// XRNK — faction rank required to use the reference freely. Meaningful
    /// only when `owner` is a FACT; nil when the field is absent.
    let ownerFactionRank: Int32?
    /// XCNT — how many of the base item this reference places. Nil when
    /// absent, which means one.
    let itemCount: Int32?
    /// VMAD — Papyrus scripts attached directly to this placed reference.
    let scriptData: ScriptData

    /// The link `ObjectReference.GetLinkedRef(akKeyword)` resolves to: the
    /// first entry tagged with `keyword`, or — passing `nil`, the Papyrus
    /// default — the first entry that carries no keyword at all. Returns nil
    /// when no entry matches, which is `GetLinkedRef` returning `None`.
    ///
    /// File order decides ties, but nothing in Skyrim.esm needs a tiebreak:
    /// the sweep in `PlacedReferenceLinkedRefRealDataTests` finds no reference
    /// that repeats a keyword and none that carries more than one untagged
    /// link, so first-match and only-match agree on real data. The deepest
    /// list observed is 19 links.
    func linkedReference(keyword: FormID? = nil) -> FormID? {
        linkedReferences.first { $0.keyword == keyword }?.ref
    }

    init(record: ESMRecord) throws {
        guard record.type == "REFR" else {
            throw ESMError.malformed("expected REFR record, got \(record.type)")
        }
        formID = FormID(record.formID)

        var base: FormID?
        var placement: Placement?
        var optionals = Optionals()
        var scriptData = ScriptData(ownerType: record.type)
        for field in try record.fields() {
            switch field.type {
            case "NAME":
                var reader = BinaryReader(field.data)
                base = try FormID(reader.readUInt32())
            case "DATA":
                placement = try Self.decodePlacement(field.data)
            default:
                if try !optionals.decode(field: field, reference: formID) {
                    _ = try scriptData.decode(field: field)
                }
            }
        }
        guard let base else {
            throw ESMError.malformed("REFR \(formID) has no NAME field")
        }
        guard let placement else {
            throw ESMError.malformed("REFR \(formID) has no DATA field")
        }
        self.base = base
        self.placement = placement
        scale = optionals.scale
        teleportDestination = optionals.teleportDestination
        lightRadius = optionals.lightRadius
        emittance = optionals.emittance
        primitive = optionals.primitive
        linkedReferences = optionals.linkedReferences
        owner = optionals.owner
        ownerFactionRank = optionals.ownerFactionRank
        itemCount = optionals.itemCount
        self.scriptData = scriptData
    }

    /// Accumulator for the optional REFR subrecords. It exists so the field
    /// switch lives in its own function: `init(record:)` plus every optional
    /// case in one body runs past the cyclomatic-complexity limit, and every
    /// new subrecord would push it further.
    private struct Optionals {
        var scale: Float = 1
        var teleportDestination: TeleportDestination?
        var lightRadius: Float?
        var emittance: FormID?
        var primitive: Primitive?
        var linkedReferences: [LinkedReference] = []
        var owner: FormID?
        var ownerFactionRank: Int32?
        var itemCount: Int32?

        /// Decodes `field` when it is one of the optional subrecords and
        /// reports whether it was consumed; false leaves it to `ScriptData`.
        mutating func decode(field: ESMField, reference: FormID) throws -> Bool {
            switch field.type {
            case "XSCL":
                var reader = BinaryReader(field.data)
                scale = try Float(bitPattern: reader.readUInt32())
            case "XTEL":
                teleportDestination = try PlacedReference.decodeTeleport(
                    field, reference: reference
                )
            case "XRDS":
                lightRadius = try PlacedReference.decodeFloat(field.data)
            case "XEMI":
                emittance = try PlacedReference.decodeFormID(field.data)
            case "XPRM":
                primitive = try PlacedReference.decodePrimitive(field, reference: reference)
            case "XLKR":
                PlacedReference.appendLinkedReference(field.data, to: &linkedReferences)
            case "XOWN":
                owner = try InventoryItemFields.optionalFormID(field)
            case "XRNK":
                ownerFactionRank = try PlacedReference.decodeInt32(field.data)
            case "XCNT":
                itemCount = try PlacedReference.decodeInt32(field.data)
            default:
                return false
            }
            return true
        }
    }

    /// DATA: position xyz then rotation xyz, all little-endian float32.
    private static func decodePlacement(_ data: Data) throws -> Placement {
        var reader = BinaryReader(data)
        return try Placement(
            position: SIMD3(
                Float(bitPattern: reader.readUInt32()),
                Float(bitPattern: reader.readUInt32()),
                Float(bitPattern: reader.readUInt32())
            ),
            rotation: SIMD3(
                Float(bitPattern: reader.readUInt32()),
                Float(bitPattern: reader.readUInt32()),
                Float(bitPattern: reader.readUInt32())
            )
        )
    }

    private static func decodeFloat(_ data: Data) throws -> Float? {
        guard data.count >= 4 else { return nil }
        var reader = BinaryReader(data)
        return try reader.readFloat32()
    }

    /// Reads a signed 32-bit count/rank word, or nil when the payload is too
    /// short to hold one — an unreadable XRNK/XCNT degrades to "not set".
    private static func decodeInt32(_ data: Data) throws -> Int32? {
        guard data.count >= 4 else { return nil }
        var reader = BinaryReader(data)
        return try Int32(bitPattern: reader.readUInt32())
    }

    private static func decodeFormID(_ data: Data) throws -> FormID? {
        guard data.count >= 4 else { return nil }
        var reader = BinaryReader(data)
        return try FormID(reader.readUInt32())
    }

    /// Decodes one XLKR payload and appends it when it is readable.
    ///
    /// Unlike XTEL this never throws: XLKR is a repeating optional link, so a
    /// payload of an unexpected length costs the engine one link, whereas a
    /// wrong-size XTEL would silently teleport a door to the wrong place. A
    /// short or unrecognised payload is therefore skipped, matching
    /// `decodeFloat`/`decodeFormID` above.
    ///
    /// Layout: 8 bytes = keyword FormID then linked-reference FormID; 4 bytes
    /// = the linked reference alone. Trailing bytes past the struct are
    /// ignored rather than treated as a second entry, because the subrecord
    /// repeats instead of packing an array. Skyrim.esm only ever uses 4 and 8;
    /// every other length is a mod-quirk path.
    private static func appendLinkedReference(
        _ data: Data,
        to links: inout [LinkedReference]
    ) {
        var reader = BinaryReader(data)
        guard let first = try? FormID(reader.readUInt32()) else { return }
        if data.count >= 8, let second = try? FormID(reader.readUInt32()) {
            links.append(LinkedReference(keyword: first.isNull ? nil : first, ref: second))
        } else {
            links.append(LinkedReference(keyword: nil, ref: first))
        }
    }

    private static func decodeTeleport(
        _ field: ESMField,
        reference: FormID
    ) throws -> TeleportDestination {
        // UESP REFR + xEdit wbDefinitionsTES5.pas: exact 32-byte struct =
        // REFR FormID, position xyz, rotation xyz, uint32 flags.
        guard field.data.count == 32 else {
            throw ESMError.malformed(
                "REFR \(reference) XTEL has \(field.data.count) bytes, expected 32"
            )
        }
        var reader = BinaryReader(field.data)
        return try TeleportDestination(
            door: FormID(reader.readUInt32()),
            placement: Placement(
                position: SIMD3(
                    Float(bitPattern: reader.readUInt32()),
                    Float(bitPattern: reader.readUInt32()),
                    Float(bitPattern: reader.readUInt32())
                ),
                rotation: SIMD3(
                    Float(bitPattern: reader.readUInt32()),
                    Float(bitPattern: reader.readUInt32()),
                    Float(bitPattern: reader.readUInt32())
                )
            ),
            flags: TeleportDestination.Flags(rawValue: reader.readUInt32())
        )
    }
}
