// The material a Skyrim NIF stores on a collision shape is not an enumeration
// the engine assigns numbers to: it is a hash of the material's Creation Kit
// name. That is what lets a plugin author a new material and have meshes point
// at it without a NIF format change, and it is the link that turns a Havok
// material value back into the MATT record an impact table is keyed by.
//
// Reference: NifTools nif.xml, enum `SkyrimHavokMaterial` — "Material
// descriptor for a Havok shape in Skyrim. CRC32 of the lowercase of the
// Creation Kit Material Name."
//   https://github.com/niftools/nifxml/blob/develop/nif.xml
//
// The variant is the reflected polynomial 0xEDB88320 with a zero initial
// register and no final complement: the familiar CRC-32 table without zlib's
// pre- and post-inversion. nif.xml says "CRC32" and stops there, so the
// parameters were recovered by search and then confirmed against every named
// value the enum lists (`HavokMaterialHashTests`).

nonisolated enum HavokMaterialHash {
    /// The Havok material value a NIF stores for `name`, which is `MATT.MNAM`.
    static func value(ofMaterialName name: String) -> UInt32 {
        var register: UInt32 = 0
        for byte in name.lowercased().utf8 {
            register = table[Int((register ^ UInt32(byte)) & 0xFF)] ^ (register >> 8)
        }
        return register
    }

    private static let table: [UInt32] = (0 ..< 256).map { index in
        var value = UInt32(index)
        for _ in 0 ..< 8 {
            value = value & 1 == 1 ? (value >> 1) ^ 0xEDB8_8320 : value >> 1
        }
        return value
    }
}
