// OBND, the axis-aligned bounding box every placeable base record carries.
// Twelve bytes, six little-endian int16 in the order X1 Y1 Z1 X2 Y2 Z2 — the
// minimum corner then the maximum corner, in game units, relative to the
// record's own origin. Vanilla writes the field even when every component is
// zero, which is why so many records show "12 zeroes most of the time".
//
// Shared rather than repeated: MISC, BOOK, ALCH, INGR, WEAP, AMMO, CONT and
// ARMO all carry the same field, and so does most of the rest of the object
// tree. Mirrors the standalone `BodyTemplate` helper pattern.
//
// References:
//   UESP "Skyrim Mod:Mod File Format" per-record pages list OBND on every
//   placeable base record, e.g.
//   https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/MISC
//   xEdit dev-4.1.6 Core/wbDefinitionsCommon.pas `wbOBND` (line 8634) is the
//   authority for the component order and int16 typing.
// Layout documented in docs/formats/records.md.

import Foundation

nonisolated struct ObjectBounds: Equatable {
    /// Minimum corner (X1, Y1, Z1) in game units.
    let minimum: SIMD3<Int16>
    /// Maximum corner (X2, Y2, Z2) in game units.
    let maximum: SIMD3<Int16>

    /// True when every component is zero — the "no meaningful bounds" case
    /// vanilla writes for records whose volume the engine never queries.
    var isEmpty: Bool {
        minimum == .zero && maximum == .zero
    }

    /// Decodes an OBND payload. A field shorter than 12 bytes is structurally
    /// unusable, so it throws rather than inventing a box; callers that would
    /// rather skip the record catch and continue per the mod-quirk rule.
    init(field: ESMField) throws {
        guard field.data.count >= 12 else {
            throw ESMError.malformed(
                "OBND has \(field.data.count) bytes, expected 12"
            )
        }
        var reader = BinaryReader(field.data)
        minimum = try SIMD3(
            Int16(bitPattern: reader.readUInt16()),
            Int16(bitPattern: reader.readUInt16()),
            Int16(bitPattern: reader.readUInt16())
        )
        maximum = try SIMD3(
            Int16(bitPattern: reader.readUInt16()),
            Int16(bitPattern: reader.readUInt16()),
            Int16(bitPattern: reader.readUInt16())
        )
    }
}
