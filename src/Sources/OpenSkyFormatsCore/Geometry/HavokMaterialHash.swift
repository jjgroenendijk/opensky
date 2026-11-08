// A NIF collision material is the CRC32 of the lowercase Creation Kit material
// name, so a plugin can add materials without a NIF change. The CRC variant
// has no pre- or post-inversion. Source: docs/formats/material-type.md.

nonisolated public enum HavokMaterialHash: Sendable {
    /// The Havok material value a NIF stores for `name`, which is `MATT.MNAM`.
    public static func value(ofMaterialName name: String) -> UInt32 {
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
