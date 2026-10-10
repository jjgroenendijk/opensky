// Writers for the save's own types, for building synthetic `.ess` parts in code.

import Foundation
import OpenSkyFormatsCore

public enum ESSBytes {
    public static func wstring(_ text: String, into writer: inout BinaryWriter) {
        let bytes = Data(text.utf8)
        writer.writeUInt16(UInt16(bytes.count))
        writer.write(bytes)
    }

    /// The smallest width that holds `value`.
    public static func vsval(_ value: UInt32, into writer: inout BinaryWriter) {
        if value < 0x40 {
            writer.writeUInt8(UInt8(value << 2))
        } else if value < 0x4000 {
            writer.writeUInt16(UInt16(value << 2 | 1))
        } else {
            let packed = value << 2 | 2
            writer.writeUInt16(UInt16(packed & 0xFFFF))
            writer.writeUInt8(UInt8(packed >> 16))
        }
    }

    /// Kind 0 indexes the form id array (one past), 1 is `Skyrim.esm`, 2 is created.
    public static func refID(kind: UInt8, value: UInt32, into writer: inout BinaryWriter) {
        let raw = UInt32(kind) << 22 | (value & 0x003F_FFFF)
        writer.writeUInt8(UInt8(raw >> 16 & 0xFF))
        writer.writeUInt8(UInt8(raw >> 8 & 0xFF))
        writer.writeUInt8(UInt8(raw & 0xFF))
    }

    public static func vector3(_ value: SIMD3<Float>, into writer: inout BinaryWriter) {
        writer.writeFloat32(value.x)
        writer.writeFloat32(value.y)
        writer.writeFloat32(value.z)
    }

    public static func build(_ body: (inout BinaryWriter) -> Void) -> Data {
        var writer = BinaryWriter()
        body(&writer)
        return writer.data
    }

    /// A raw LZ4 block holding `payload` as literals only, which every decoder reads.
    public static func lz4LiteralBlock(_ payload: Data) -> Data {
        var block = Data()
        let length = payload.count
        block.append(UInt8(min(length, 15)) << 4)
        if length >= 15 {
            var rest = length - 15
            while rest >= 255 {
                block.append(255)
                rest -= 255
            }
            block.append(UInt8(rest))
        }
        block.append(payload)
        return block
    }
}
