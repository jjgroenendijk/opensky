// Skyrim `.lip` payload: a 12-byte header, then a zero-run compressed body that
// expands to a dense frame-by-frame grid of float32 curve values at 30 frames per
// second. Layout and evidence: docs/formats/lip.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public enum LIPError: Error, Equatable, Sendable {
    case malformed(String)
    case unsupported(String)
}

nonisolated public struct LIPHeader: Equatable, Sendable {
    /// The expanded size the file declares. It is the expanded body plus 16 bytes.
    public let expandedSize: Int
    /// Curves with any motion in the line. Kept, not checked.
    public let activeCurveCount: Int
    public let frameCount: Int
    /// The audio frame of grid row 0. Usually negative: rows before the audio starts.
    public let firstFrame: Int
    /// Speech targets: 16 for humanoid heads, 8 for creatures.
    public let targetCount: Int
    public let slotsPerFrame: Int
}

nonisolated public struct LIPSample: Equatable, Sendable {
    /// One value per slot, in slot order.
    public let values: [Float]

    public init(values: [Float]) {
        self.values = values
    }

    public func value(at slot: Int) -> Float {
        values.indices.contains(slot) ? values[slot] : 0
    }
}

nonisolated public struct LIPFile: Equatable, Sendable {
    public static let framesPerSecond = 30.0
    /// 16 speech targets, 14 face modifiers, and 3 head angles.
    public static let humanoidSlotsPerFrame = 33

    public let header: LIPHeader
    /// `frameCount * slotsPerFrame` values, frame by frame.
    public let values: [Float]

    public init(data: Data) throws {
        do {
            self = try LIPDecoder(data: data).decode()
        } catch let error as LIPError {
            throw error
        } catch {
            throw LIPError.malformed(String(describing: error))
        }
    }

    fileprivate init(header: LIPHeader, values: [Float]) {
        self.header = header
        self.values = values
    }

    public var duration: Double {
        Double(header.firstFrame + header.frameCount) / Self.framesPerSecond
    }

    public func value(frame: Int, slot: Int) -> Float {
        guard
            (0 ..< header.frameCount).contains(frame),
            (0 ..< header.slotsPerFrame).contains(slot)
        else { return 0 }
        return values[frame * header.slotsPerFrame + slot]
    }

    /// Slots that are not zero in at least one frame.
    public var activeSlots: [Int] {
        (0 ..< header.slotsPerFrame).filter { slot in
            (0 ..< header.frameCount).contains { value(frame: $0, slot: slot) != 0 }
        }
    }

    /// The grid at audio time `seconds`, linear between frames and held at both ends.
    public func sample(at seconds: Double) -> LIPSample {
        let safeSeconds = seconds.isFinite ? max(0, seconds) : 0
        let row = safeSeconds * Self.framesPerSecond - Double(header.firstFrame)
        let clamped = min(max(row, 0), Double(header.frameCount - 1))
        let lower = Int(clamped)
        let upper = min(lower + 1, header.frameCount - 1)
        let fraction = Float(clamped - Double(lower))
        return LIPSample(values: (0 ..< header.slotsPerFrame).map { slot in
            let from = value(frame: lower, slot: slot)
            return from + (value(frame: upper, slot: slot) - from) * fraction
        })
    }
}

nonisolated private struct LIPDecoder {
    private enum Layout {
        static let version: UInt32 = 1
        static let headerSize = 12
        static let bodyHeaderSize = 12
        /// The declared expanded size counts 16 bytes more than the body.
        static let expandedSizeBias = 16
        /// Far above the longest vanilla line, and a guard against a hostile size.
        static let maximumExpandedSize = 64 << 20
        static let maximumTargetCount = 64
        /// Ten minutes in. Vanilla starts no grid later than frame 22.
        static let latestFirstFrame = 18000
    }

    private let data: Data

    init(data: Data) {
        self.data = data
    }

    func decode() throws -> LIPFile {
        var reader = BinaryReader(data)
        guard data.count >= Layout.headerSize else {
            throw LIPError.malformed("file is shorter than the 12-byte header")
        }
        let version = try reader.readUInt32()
        guard version == Layout.version else {
            throw LIPError.unsupported("animation version \(version)")
        }
        let expandedSize = try Int(reader.readUInt32())
        let activeCurveCount = try Int(reader.readUInt32())
        let bodySize = expandedSize - Layout.expandedSizeBias
        guard bodySize >= Layout.bodyHeaderSize, expandedSize <= Layout.maximumExpandedSize else {
            throw LIPError.unsupported("expanded size \(expandedSize)")
        }
        let body = try LIPZeroRun.expand(data.dropFirst(Layout.headerSize), to: bodySize)
        return try readBody(body, expandedSize: expandedSize, activeCurveCount: activeCurveCount)
    }

    private func readBody(
        _ body: Data, expandedSize: Int, activeCurveCount: Int
    ) throws -> LIPFile {
        var reader = BinaryReader(body)
        let frameCount = try Int(reader.readUInt32())
        let firstFrame = try Int(Int32(bitPattern: reader.readUInt32()))
        let targetCount = try Int(reader.readUInt32())
        guard frameCount > 0 else { throw LIPError.malformed("frame count is zero") }
        guard (-frameCount ... Layout.latestFirstFrame).contains(firstFrame) else {
            throw LIPError.malformed("first frame \(firstFrame) for \(frameCount) frames")
        }
        let gridBytes = body.count - Layout.bodyHeaderSize
        guard gridBytes.isMultiple(of: 4 * frameCount) else {
            throw LIPError.malformed("\(gridBytes) grid bytes do not fill \(frameCount) frames")
        }
        let slotsPerFrame = gridBytes / (4 * frameCount)
        guard (1 ... Layout.maximumTargetCount).contains(targetCount), slotsPerFrame >= targetCount
        else {
            throw LIPError.unsupported("\(targetCount) targets on \(slotsPerFrame) slots")
        }
        var values: [Float] = []
        values.reserveCapacity(frameCount * slotsPerFrame)
        for _ in 0 ..< frameCount * slotsPerFrame {
            let value = try reader.readFloat32()
            guard value.isFinite else { throw LIPError.malformed("non-finite curve value") }
            values.append(value)
        }
        let header = LIPHeader(
            expandedSize: expandedSize,
            activeCurveCount: activeCurveCount,
            frameCount: frameCount,
            firstFrame: firstFrame,
            targetCount: targetCount,
            slotsPerFrame: slotsPerFrame
        )
        return LIPFile(header: header, values: values)
    }
}

/// A `00` byte and a uint16 count stand for that many zero bytes; every other byte
/// is itself. The grid is mostly zeros, so this is most of the saving.
nonisolated public enum LIPZeroRun {
    public static func expand(_ packed: some Collection<UInt8>, to size: Int) throws -> Data {
        var output = Data(capacity: size)
        var index = packed.startIndex
        while index != packed.endIndex {
            let byte = packed[index]
            index = packed.index(after: index)
            guard byte == 0 else {
                output.append(byte)
                guard output.count <= size else { throw overrun(size) }
                continue
            }
            guard packed.distance(from: index, to: packed.endIndex) >= 2 else {
                throw LIPError.malformed("zero run is cut off at the end")
            }
            let low = Int(packed[index])
            let high = Int(packed[packed.index(after: index)])
            index = packed.index(index, offsetBy: 2)
            let count = low | high << 8
            guard output.count + count <= size else { throw overrun(size) }
            output.append(contentsOf: repeatElement(0, count: count))
        }
        guard output.count == size else {
            throw LIPError.malformed("body expands to \(output.count) bytes, header says \(size)")
        }
        return output
    }

    /// The inverse of `expand`, used to build test files.
    public static func pack(_ bytes: some Sequence<UInt8>) -> Data {
        var output = Data()
        var zeros = 0
        func flush() {
            while zeros > 0 {
                let count = min(zeros, Int(UInt16.max))
                output.append(contentsOf: [0, UInt8(count & 0xFF), UInt8(count >> 8)])
                zeros -= count
            }
        }
        for byte in bytes {
            if byte == 0 {
                zeros += 1
            } else {
                flush()
                output.append(byte)
            }
        }
        flush()
        return output
    }

    private static func overrun(_ size: Int) -> LIPError {
        .malformed("body expands past the \(size) bytes the header gives")
    }
}
