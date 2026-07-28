// Save-flavoured cursor over save bytes (issue #161).
//
// `BinaryReader` already does the bounds checking; this wrapper exists so the
// decoder never has to hand a `BinaryReaderError` to its caller. Running out
// of bytes always means the file is truncated inside some named structure, so
// every read takes the name of that structure and every reader failure becomes
// `OpenSkySaveError.truncated(context:)`. Value-typed like the reader it
// wraps, so a chunk payload is decoded by making a fresh `SaveReader` over the
// payload slice and letting its bounds do the containment for free.

import Foundation

nonisolated struct SaveReader {
    private var reader: BinaryReader

    init(_ data: Data) {
        reader = BinaryReader(data)
    }

    var bytesRemaining: Int {
        reader.bytesRemaining
    }

    var isAtEnd: Bool {
        reader.bytesRemaining == 0
    }

    mutating func bytes(_ count: Int, _ context: String) throws -> Data {
        guard count >= 0, count <= reader.bytesRemaining else {
            throw OpenSkySaveError.truncated(context: context)
        }
        do {
            return try reader.read(count: count)
        } catch {
            throw OpenSkySaveError.truncated(context: context)
        }
    }

    mutating func uint8(_ context: String) throws -> UInt8 {
        do {
            return try reader.readUInt8()
        } catch {
            throw OpenSkySaveError.truncated(context: context)
        }
    }

    mutating func uint16(_ context: String) throws -> UInt16 {
        do {
            return try reader.readUInt16()
        } catch {
            throw OpenSkySaveError.truncated(context: context)
        }
    }

    mutating func uint32(_ context: String) throws -> UInt32 {
        do {
            return try reader.readUInt32()
        } catch {
            throw OpenSkySaveError.truncated(context: context)
        }
    }

    mutating func uint64(_ context: String) throws -> UInt64 {
        do {
            return try reader.readUInt64()
        } catch {
            throw OpenSkySaveError.truncated(context: context)
        }
    }

    mutating func float32(_ context: String) throws -> Float {
        do {
            return try reader.readFloat32()
        } catch {
            throw OpenSkySaveError.truncated(context: context)
        }
    }

    /// UInt16 byte length + UTF-8 bytes. A length past the end of the data is
    /// a truncation, not an allocation: the bytes are never reserved first.
    mutating func string(_ context: String) throws -> String {
        let length = try Int(uint16(context))
        let raw = try bytes(length, context)
        guard let text = String(data: raw, encoding: .utf8) else {
            throw OpenSkySaveError.invalidValue(context: "\(context) is not valid UTF-8")
        }
        return text
    }

    /// A byte the format defines as 0 or 1. Anything else is corruption, not
    /// a truthy value: silently treating 0x7F as `true` would hide a decoder
    /// or writer bug behind a plausible-looking world.
    mutating func bool(_ context: String) throws -> Bool {
        let value = try uint8(context)
        switch value {
        case 0:
            return false
        case 1:
            return true
        default:
            throw OpenSkySaveError.invalidValue(context: "\(context) has non-boolean byte \(value)")
        }
    }
}
