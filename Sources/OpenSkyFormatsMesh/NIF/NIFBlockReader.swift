// Field readers the typed block decoders share: string-table names, sized
// strings, ref lists, and the `NiTimeController` part every controller starts
// with. Layout: docs/formats/nif.md.

import Foundation
import OpenSkyFormatsCore

nonisolated extension BinaryReader {
    /// A string-table index. Nil for -1 or an index past the table: vanilla tables
    /// hold exporter junk, and a bad name must not reject the mesh.
    public mutating func readNIFString(_ header: NIFHeader) throws -> String? {
        let index = try readUInt32()
        guard index != .max, Int(index) < header.strings.count else { return nil }
        return header.strings[Int(index)]
    }

    /// nif.xml `SizedString`: a uint32 length, then the bytes with no null.
    public mutating func readNIFSizedString() throws -> String {
        let length = try Int(readUInt32())
        guard length <= bytesRemaining else {
            throw NIFError.malformed("string length \(length) exceeds block size")
        }
        return try GameText.decode(read(count: length))
    }

    /// A uint32 count, then that many int32 block refs (-1 is an empty slot).
    public mutating func readNIFRefs(label: String) throws -> [Int32] {
        let count = try readNIFCount(stride: 4, label: label)
        return try (0 ..< count).map { _ in try readNIFRef() }
    }

    /// A uint32 count whose items of `stride` bytes must fit in the block.
    public mutating func readNIFCount(stride: Int, label: String) throws -> Int {
        try checkNIFCount(Int(readUInt32()), stride: stride, label: label)
    }

    /// A uint16 count whose items of `stride` bytes must fit in the block.
    public mutating func readNIFShortCount(stride: Int, label: String) throws -> Int {
        try checkNIFCount(Int(readUInt16()), stride: stride, label: label)
    }

    func checkNIFCount(_ count: Int, stride: Int, label: String) throws -> Int {
        guard count * stride <= bytesRemaining else {
            throw NIFError.malformed("\(label) count \(count) exceeds block size")
        }
        return count
    }
}

/// nif.xml `NiTimeController`: next controller, flags, timing, and target.
nonisolated public struct NIFTimeController: Equatable, Sendable {
    /// Next controller, flags, frequency, phase, start, stop, target.
    public static let size = 4 + 2 + 4 * 4 + 4

    public let nextControllerRef: Int32
    /// nif.xml `TimeControllerFlags`.
    public let flags: UInt16
    public let timing: ControllerTiming
    public let targetRef: Int32

    public init(reader: inout BinaryReader) throws {
        nextControllerRef = try reader.readNIFRef()
        flags = try reader.readUInt16()
        let frequency = try reader.readFloat32()
        let phase = try reader.readFloat32()
        let start = try reader.readFloat32()
        let stop = try reader.readFloat32()
        timing = ControllerTiming(
            cycle: ControllerCycle(rawValue: (flags >> 1) & 0x3) ?? .clamp,
            frequency: frequency, phase: phase, startTime: start, stopTime: stop
        )
        targetRef = try reader.readNIFRef()
    }

    /// Flag bit 3. An inactive controller leaves its target alone.
    public var isActive: Bool {
        flags & 0x8 != 0
    }

    /// Flag bit 5: a controller manager's sequences feed it.
    public var isManagerControlled: Bool {
        flags & 0x20 != 0
    }
}

/// nif.xml `NiSingleInterpController`: a time controller and one interpolator.
nonisolated public struct NIFInterpolatedController: Equatable, Sendable {
    public let controller: NIFTimeController
    public let interpolatorRef: Int32

    public init(reader: inout BinaryReader) throws {
        controller = try NIFTimeController(reader: &reader)
        interpolatorRef = try reader.readNIFRef()
    }
}
