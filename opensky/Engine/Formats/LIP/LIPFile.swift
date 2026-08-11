// Skyrim `.lip` facial-animation payload: a 24-byte FaceFX animation header
// followed by sparse float tokens routed over a 33-slot, 30 Hz frame grid.
//
// The byte model comes from the clean-room OpenFaceFX research codec and was
// checked against the user's installed voice corpus. The payload does not name
// phonemes or TRI targets; it carries positional slots. Keep that distinction
// in the types so an inferred mapping cannot become an asserted on-disk fact.
//
// Reference:
// https://github.com/OpenFaceFX/OpenFaceFX/blob/main/tools/lip_codec_research.py
// Local evidence and the confirmed-versus-uncertain split are documented in
// docs/formats/lip.md.

import Foundation

nonisolated enum LIPError: Error, Equatable {
    case malformed(String)
    case unsupported(String)
}

nonisolated struct LIPHeader: Equatable {
    let durationTicks: UInt32
    let activeCurveCount: UInt32
    let frameCount: Int
    let firstFrame: Int
    let unknownValue: UInt16
}

nonisolated struct LIPKey: Equatable {
    let frame: Int
    let slot: Int
    let value: Float
    /// The payload repeated the same Float32 bytes immediately after `value`.
    /// OpenFaceFX identifies this as an equal-tangent encoding. OpenSky tallies
    /// it but samples only the first value until that semantic is confirmed.
    let hasDuplicate: Bool
}

nonisolated struct LIPSample: Equatable {
    let trackTime: Double
    let weightsBySlot: [Int: Float]
}

nonisolated private struct LIPDecodedKeys {
    let keys: [LIPKey]
    let duplicateCount: Int
    let markerCount: Int
}

nonisolated struct LIPFile: Equatable {
    static let framesPerSecond = 30.0
    static let slotCount = 33
    static let speechTargetCount = 16

    let header: LIPHeader
    let keys: [LIPKey]
    let duplicateValueCount: Int
    let markerCount: Int
    let unmappedKeyCount: Int

    init(data: Data) throws {
        do {
            var decoder = LIPDecoder(data: data)
            self = try decoder.decode()
        } catch let error as LIPError {
            throw error
        } catch {
            throw LIPError.malformed(String(describing: error))
        }
    }

    init(header: LIPHeader, keys: [LIPKey]) {
        self.header = header
        self.keys = keys
        duplicateValueCount = keys.count(where: \.hasDuplicate)
        markerCount = 0
        unmappedKeyCount = keys.count { !LipVisemeMapping.mappedSlots.contains($0.slot) }
    }

    var duration: Double {
        Double(header.firstFrame + header.frameCount) / Self.framesPerSecond
    }

    func sample(at seconds: Double) -> LIPSample {
        let safeSeconds = seconds.isFinite ? max(0, seconds) : 0
        let frame = safeSeconds * Self.framesPerSecond - Double(header.firstFrame)
        let maximumFrame = Double(max(0, header.frameCount - 1))
        let clampedFrame = min(max(frame, 0), maximumFrame)
        let grouped = Dictionary(grouping: keys, by: \.slot)
        let weights = grouped.mapValues { Self.sample($0, at: clampedFrame) }
        return LIPSample(trackTime: safeSeconds, weightsBySlot: weights)
    }

    private static func sample(_ keys: [LIPKey], at frame: Double) -> Float {
        guard let first = keys.first else { return 0 }
        guard frame > Double(first.frame) else { return clamped(first.value) }
        guard let last = keys.last else { return 0 }
        guard frame < Double(last.frame) else { return clamped(last.value) }
        for pair in zip(keys, keys.dropFirst()) {
            let lower = pair.0
            let upper = pair.1
            guard frame <= Double(upper.frame) else { continue }
            let span = upper.frame - lower.frame
            guard span > 0 else { return clamped(upper.value) }
            let fraction = Float((frame - Double(lower.frame)) / Double(span))
            return clamped(lower.value + (upper.value - lower.value) * fraction)
        }
        return clamped(last.value)
    }

    private static func clamped(_ value: Float) -> Float {
        min(max(value.isFinite ? value : 0, 0), 1)
    }
}

nonisolated private struct LIPDecoder {
    private enum Layout {
        static let headerSize = 24
        static let version: UInt32 = 1
        static let tupleWidth: UInt16 = 3
        static let targetCount: UInt16 = 16
        static let ticksPerFrame: UInt32 = 132
        static let durationBias: UInt32 = 28
    }

    private let data: Data
    private var reader: BinaryReader

    init(data: Data) {
        self.data = data
        reader = BinaryReader(data)
    }

    mutating func decode() throws -> LIPFile {
        let header = try readHeader()
        let decoded = try readKeys(frameCount: header.frameCount)
        return LIPFile(
            header: header,
            keys: decoded.keys,
            duplicateValueCount: decoded.duplicateCount,
            markerCount: decoded.markerCount,
            unmappedKeyCount: decoded.keys.count {
                !LipVisemeMapping.mappedSlots.contains($0.slot)
            }
        )
    }

    private mutating func readHeader() throws -> LIPHeader {
        guard reader.bytesRemaining >= Layout.headerSize else {
            throw LIPError.malformed("file is shorter than the 24-byte header")
        }
        let version = try reader.readUInt32()
        guard version == Layout.version else {
            throw LIPError.unsupported("animation version \(version)")
        }
        let durationTicks = try reader.readUInt32()
        let activeCurveCount = try reader.readUInt32()
        let frameCount = try Int(reader.readUInt16())
        let tupleWidth = try reader.readUInt16()
        let firstFrame = try Int(Int32(bitPattern: reader.readUInt32()))
        let targetCount = try reader.readUInt16()
        let unknownValue = try reader.readUInt16()
        guard frameCount > 0 else { throw LIPError.malformed("frame count is zero") }
        guard tupleWidth == Layout.tupleWidth else {
            throw LIPError.unsupported("key tuple width \(tupleWidth)")
        }
        guard targetCount == Layout.targetCount else {
            throw LIPError.unsupported("target vocabulary \(targetCount)")
        }
        guard activeCurveCount <= UInt32(targetCount) else {
            throw LIPError.malformed(
                "active curve count \(activeCurveCount) exceeds target count \(targetCount)"
            )
        }
        guard firstFrame <= 0, firstFrame >= -frameCount else {
            throw LIPError.malformed(
                "first frame \(firstFrame) is outside -\(frameCount)...0"
            )
        }
        let expectedTicks = UInt32(frameCount) * Layout.ticksPerFrame + Layout.durationBias
        guard durationTicks == expectedTicks else {
            throw LIPError.malformed(
                "duration ticks \(durationTicks), expected \(expectedTicks) "
                    + "for \(frameCount) frames"
            )
        }
        return LIPHeader(
            durationTicks: durationTicks,
            activeCurveCount: activeCurveCount,
            frameCount: frameCount,
            firstFrame: firstFrame,
            unknownValue: unknownValue
        )
    }

    private mutating func readKeys(
        frameCount: Int
    ) throws -> LIPDecodedKeys {
        var keys: [LIPKey] = []
        var position = 0
        var duplicates = 0
        var markers = 0
        let maximumPosition = frameCount * LIPFile.slotCount
        while reader.bytesRemaining >= 4 {
            let rawValue = try reader.read(count: 4)
            let bits = rawValue.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
            let value = Float(bitPattern: UInt32(littleEndian: bits))
            guard value.isFinite else {
                throw LIPError.malformed("non-finite curve value at byte \(reader.offset - 4)")
            }
            let duplicate = nextBytes(count: 4) == rawValue
            if duplicate {
                _ = try reader.read(count: 4)
                duplicates += 1
            }
            let gap = try readMarkerGap()
            if gap > 0 {
                markers += 1
            }
            guard position < maximumPosition else {
                throw LIPError.malformed("curve position \(position) exceeds frame grid")
            }
            keys.append(LIPKey(
                frame: position / LIPFile.slotCount,
                slot: position % LIPFile.slotCount,
                value: value,
                hasDuplicate: duplicate
            ))
            position += (duplicate ? 2 : 1) + gap
            guard position <= maximumPosition else {
                throw LIPError.malformed("curve stream overruns \(frameCount) frames")
            }
        }
        guard reader.bytesRemaining == 0 else {
            throw LIPError.malformed("\(reader.bytesRemaining) trailing payload bytes")
        }
        guard !keys.isEmpty else { throw LIPError.malformed("curve payload is empty") }
        return LIPDecodedKeys(
            keys: keys,
            duplicateCount: duplicates,
            markerCount: markers
        )
    }

    private mutating func readMarkerGap() throws -> Int {
        guard let bytes = nextBytes(count: 3), bytes[0] == 0, bytes[2] == 0 else {
            return 0
        }
        let tag = bytes[1]
        guard tag != 0, tag.isMultiple(of: 4) else { return 0 }
        _ = try reader.read(count: 3)
        return Int(tag / 4)
    }

    private func nextBytes(count: Int) -> Data? {
        guard reader.bytesRemaining >= count else { return nil }
        return data.subdata(in: reader.offset ..< reader.offset + count)
    }
}

nonisolated extension LIPFile {
    fileprivate init(
        header: LIPHeader,
        keys: [LIPKey],
        duplicateValueCount: Int,
        markerCount: Int,
        unmappedKeyCount: Int
    ) {
        self.header = header
        self.keys = keys
        self.duplicateValueCount = duplicateValueCount
        self.markerCount = markerCount
        self.unmappedKeyCount = unmappedKeyCount
    }
}
