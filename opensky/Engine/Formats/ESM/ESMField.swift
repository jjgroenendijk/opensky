// Plugin field (subrecord): 4-char type + uint16 dataSize + payload.
// An XXXX field carries a uint32 that overrides the NEXT field's size (whose
// own dataSize is then 0) — used for payloads over 64 KB, e.g. NAVM/NVNM
// geometry in Skyrim.esm.
//
// Reference: UESP "Skyrim Mod:Mod File Format" — Fields.

import Foundation

nonisolated struct ESMField {
    let type: FourCC
    let data: Data

    /// Parses a record's whole field region. XXXX markers are folded into the
    /// field they extend and not emitted themselves.
    static func parseAll(_ data: Data) throws -> [ESMField] {
        var fields: [ESMField] = []
        var reader = BinaryReader(data)
        var sizeOverride: Int?
        while reader.bytesRemaining > 0 {
            let type = try reader.readFourCC()
            let declaredSize = try Int(reader.readUInt16())
            if type == "XXXX" {
                guard declaredSize == 4 else {
                    throw ESMError.malformed("XXXX field size \(declaredSize), expected 4")
                }
                guard sizeOverride == nil else {
                    throw ESMError.malformed("consecutive XXXX fields")
                }
                sizeOverride = try Int(reader.readUInt32())
                continue
            }
            let size = sizeOverride ?? declaredSize
            sizeOverride = nil
            try fields.append(ESMField(type: type, data: reader.read(count: size)))
        }
        guard sizeOverride == nil else {
            throw ESMError.malformed("dangling XXXX field at end of record")
        }
        return fields
    }
}
