// REFR placed reference: a base record at a world position, plus optional
// teleport, links, primitive, and ownership (XOWN, XRNK, XCNT). In Skyrim XOWN
// is a plain FormID. Layout and sources: docs/formats/placed-references.md.

import Foundation
import OpenSkyFormatsCore
import simd

nonisolated public struct PlacedReference: Sendable {
    /// DATA field: 24 bytes, positions in game units, rotations in radians
    /// (Skyrim world axes — see docs/decisions/coordinates.md).
    public struct Placement: Equatable, Sendable {
        public let position: SIMD3<Float>
        public let rotation: SIMD3<Float>

        public init(position: SIMD3<Float>, rotation: SIMD3<Float>) {
            self.position = position
            self.rotation = rotation
        }
    }

    /// XTEL field: destination door reference + arrival transform + flags.
    /// xEdit names the FormID target "Door" but constrains it to REFR.
    public struct TeleportDestination: Equatable, Sendable {
        public struct Flags: OptionSet, Equatable, Sendable {
            public let rawValue: UInt32

            public init(rawValue: UInt32) {
                self.rawValue = rawValue
            }

            public static let noAlarm = Flags(rawValue: 0x0000_0001)
        }

        public let door: FormID
        public let placement: Placement
        public let flags: Flags
    }

    /// One XLKR linked-reference entry. A null or absent keyword reads as
    /// `keyword == nil`. An 8-byte slot 0 is always read as a keyword, as in
    /// Skyrim.esm. Evidence: docs/formats/placed-references.md.
    public struct LinkedReference: Equatable, Sendable {
        /// KYWD tagging the link (`LinkCarryStart`, `LinkCarryEnd`, ...).
        /// `nil` when the link carries no keyword.
        public let keyword: FormID?
        /// The reference this REFR links to — a REFR/ACHR/PLYR in practice.
        public let ref: FormID
    }

    public let formID: FormID
    /// Record-header flag 0x800: hidden until a script or quest enables it.
    public let isInitiallyDisabled: Bool
    /// NAME — the base object this reference places.
    public let base: FormID
    /// DATA placement as decoded. `var` because a cell build lays a runtime
    /// transform over it first (`CellSceneBuilder.applyRuntimeState`).
    public var placement: Placement
    /// XSCL — uniform scale, defaulting to 1 when the field is absent. `var`
    /// for the same runtime-override reason as `placement`.
    public var scale: Float
    /// XTEL — present only on teleporting door references.
    public let teleportDestination: TeleportDestination?
    /// XRDS — per-reference point-light radius override.
    public let lightRadius: Float?
    /// XEMI — LIGH/REGN emittance override; LIGH handled by lighting pass.
    public let emittance: FormID?
    /// XPRM — the primitive volume this reference encloses, nil when absent.
    /// Layout and decode policy live in `PlacedReferencePrimitive.swift`.
    public let primitive: Primitive?
    /// XLKR — every linked reference, in file order. The subrecord repeats,
    /// so this is an array rather than an optional; it is empty when the
    /// reference links to nothing. Read it through
    /// `linkedReference(keyword:)` rather than by index.
    public let linkedReferences: [LinkedReference]
    /// XOWN — the NPC_ or FACT that owns this reference; nil when unowned.
    /// Taking an owned item is theft, and an owned container is a crime scene.
    public let owner: FormID?
    /// XRNK — faction rank required to use the reference freely. Meaningful
    /// only when `owner` is a FACT; nil when the field is absent.
    public let ownerFactionRank: Int32?
    /// XCNT — how many of the base item this reference places. Nil when
    /// absent, which means one.
    public let itemCount: Int32?
    /// VMAD — Papyrus scripts attached directly to this placed reference.
    public let scriptData: ScriptData
    /// XLOC. Nil when the reference is not locked.
    public let lock: LockData?
    /// XESP.
    public let enableParent: EnableParent?
    /// The XMRK group. Nil when the reference is not a map marker.
    public let mapMarker: MapMarker?
    public let details: PlacedReferenceDetails
    /// Fields this decode does not read, and malformed shared subrecords.
    public let skipped: FieldTally

    /// The link `GetLinkedRef(akKeyword)` resolves to: the first entry tagged
    /// with `keyword`, or for `nil` the first untagged entry. Nil when none
    /// matches. Skyrim.esm never needs a tiebreak.
    public func linkedReference(keyword: FormID? = nil) -> FormID? {
        linkedReferences.first { $0.keyword == keyword }?.ref
    }

    public init(record: ESMRecord) throws {
        guard record.type == "REFR" else {
            throw ESMError.malformed("expected REFR record, got \(record.type)")
        }
        formID = FormID(record.formID)
        isInitiallyDisabled = record.isInitiallyDisabled

        var base: FormID?
        var placement: Placement?
        var optionals = Optionals()
        var scriptData = ScriptData(ownerType: record.type)
        var extras = PlacedReferenceExtras()
        var unread: [ESMField] = []
        for field in try record.fields() {
            switch field.type {
            case "NAME":
                var reader = BinaryReader(field.data)
                base = try FormID(reader.readUInt32())
            case "DATA":
                placement = try Self.decodePlacement(field.data)
            default:
                if
                    try !optionals.decode(field: field, reference: formID),
                    !extras.decode(field),
                    try !scriptData.decode(field: field)
                {
                    unread.append(field)
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
        lock = extras.lock
        enableParent = extras.enableParent
        mapMarker = extras.mapMarker
        let (details, detailTally) = PlacedReferenceDetails.decode(unread)
        self.details = details
        var tally = extras.tally
        tally.merge(detailTally)
        skipped = tally
    }

    /// A reference the running game created. No record backs it, so all file
    /// fields are absent. `SpawnedReferenceIdentity` makes its `formID`, so
    /// raycasts and interaction treat it like an authored placement.
    public init(
        spawnedBase base: FormID,
        placement: Placement,
        scale: Float,
        count: Int32,
        formID: FormID
    ) {
        self.formID = formID
        isInitiallyDisabled = false
        self.base = base
        self.placement = placement
        self.scale = scale
        teleportDestination = nil
        lightRadius = nil
        emittance = nil
        primitive = nil
        linkedReferences = []
        owner = nil
        ownerFactionRank = nil
        itemCount = count
        scriptData = ScriptData(ownerType: "REFR")
        lock = nil
        enableParent = nil
        mapMarker = nil
        details = PlacedReferenceDetails()
        skipped = FieldTally()
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

    /// Decodes one XLKR payload (8 bytes: keyword, then ref; 4 bytes: ref) and
    /// appends it. Never throws: a bad payload costs one link, while a bad XTEL
    /// would move a door. Other lengths are skipped; extra bytes are ignored.
    static func appendLinkedReference(
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
