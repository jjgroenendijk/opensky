// The byte layouts every save chunk encoder shares: chunk framing, keys, cells, and
// strings. Layout: docs/formats/opensky-save.md.

import Foundation
public import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyScriptingInterface

nonisolated extension BinaryWriter {
    /// Writes `tag` plus the length-prefixed bytes `body` produces, so a
    /// decoder that does not know the tag can skip exactly the right amount.
    public mutating func writeChunk(tag: String, body: (inout BinaryWriter) -> Void) {
        var payload = BinaryWriter()
        body(&payload)
        write(Data(tag.utf8))
        writeUInt32(UInt32(clamping: payload.count))
        write(payload.data)
    }

    public mutating func writeKey(_ key: ReferenceKey) {
        switch key {
        case let .plugin(name, objectID):
            writeUInt8(OpenSkySaveFormat.KeyTag.plugin)
            writeString(name)
            writeUInt32(objectID)
        case let .generated(sequence):
            writeUInt8(OpenSkySaveFormat.KeyTag.generated)
            writeUInt64(sequence)
        }
    }

    mutating func writeCell(_ cell: CellSceneLocation?) {
        switch cell {
        case .none:
            writeUInt8(OpenSkySaveFormat.CellTag.absent)
        case let .exterior(coordinate):
            writeUInt8(OpenSkySaveFormat.CellTag.exterior)
            writeUInt32(UInt32(bitPattern: coordinate.x))
            writeUInt32(UInt32(bitPattern: coordinate.y))
        case let .interior(formID):
            writeUInt8(OpenSkySaveFormat.CellTag.interior)
            writeUInt32(formID.rawValue)
        }
    }

    /// UInt16 byte length + UTF-8 bytes. Strings longer than `UInt16.max`
    /// bytes are cut back to the last whole UTF-8 scalar that fits, so the
    /// decoder still sees valid text.
    public mutating func writeString(_ string: String) {
        let bytes = Self.truncatedUTF8(string)
        writeUInt16(UInt16(clamping: bytes.count))
        write(bytes)
    }

    private static func truncatedUTF8(_ string: String) -> Data {
        let bytes = Data(string.utf8)
        let limit = Int(UInt16.max)
        guard bytes.count > limit else { return bytes }
        var end = limit
        // 0b10xxxxxx is a UTF-8 continuation byte: back up until the cut lands
        // on a scalar boundary.
        while end > 0, bytes[bytes.startIndex + end] & 0xC0 == 0x80 {
            end -= 1
        }
        return Data(bytes.prefix(end))
    }

    /// A tag byte plus the value's payload. Floats go out as their IEEE
    /// bit pattern rather than through a decimal conversion, so the byte shape
    /// is exact and deterministic. `.object` and `.array` are written as the
    /// `none` tag: `instanceStates()` already snapshots them that way, and
    /// writing a runtime handle that means nothing after a reload would be
    /// worse than writing the type's default.
    mutating func writeScriptValue(_ value: PapyrusValue) {
        switch value {
        case .none, .object, .array:
            writeUInt8(OpenSkySaveFormat.ValueTag.none)
        case let .boolean(flag):
            writeUInt8(OpenSkySaveFormat.ValueTag.boolean)
            writeUInt8(flag ? 1 : 0)
        case let .integer(number):
            writeUInt8(OpenSkySaveFormat.ValueTag.integer)
            writeUInt32(UInt32(bitPattern: number))
        case let .float(number):
            writeUInt8(OpenSkySaveFormat.ValueTag.float)
            writeUInt32(number.bitPattern)
        case let .string(text):
            writeUInt8(OpenSkySaveFormat.ValueTag.string)
            writeString(text)
        }
    }
}
