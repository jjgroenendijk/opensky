// Skyrim `.lip` payload: a FaceFX header, then sparse float tokens over a frame
// grid of positional slots. The slots are not phonemes, and the types keep it
// so. The slot stride comes from the duration field, and some files carry a
// longer header. Byte model from OpenFaceFX; details: docs/formats/lip.md.

import Foundation

nonisolated public enum LIPError: Error, Equatable, Sendable {
    case malformed(String)
    case unsupported(String)
}

nonisolated public struct LIPHeader: Equatable, Sendable {
    public let durationTicks: UInt32
    public let activeCurveCount: UInt32
    public let frameCount: Int
    public let firstFrame: Int
    public let unknownValue: UInt16
    /// Values per key as declared at the tuple-width field: `3` for the
    /// humanoid family, `2` for the family whose header carries extra bytes.
    public let tupleWidth: Int
    /// Declared speech-target vocabulary: 16 humanoid, 8 creature.
    public let targetCount: Int
    /// Slots in one frame, derived from the tick budget rather than assumed.
    public let slotsPerFrame: Int
    /// Bytes consumed by the header, which is 24 plus any extra bytes before
    /// the tuple width.
    public let headerSize: Int
}

nonisolated public struct LIPKey: Equatable, Sendable {
    public let frame: Int
    public let slot: Int
    public let value: Float
    /// The payload repeated the same Float32 bytes immediately after `value`.
    /// OpenFaceFX identifies this as an equal-tangent encoding. OpenSky tallies
    /// it but samples only the first value until that semantic is confirmed.
    public let hasDuplicate: Bool
}

nonisolated public struct LIPSample: Equatable, Sendable {
    public let weightsBySlot: [Int: Float]
}

nonisolated public struct LIPFile: Equatable, Sendable {
    public static let framesPerSecond = 30.0
    /// The humanoid family's stride, and the one the synthetic fixtures use.
    /// A decoded file reports its own through `header.slotsPerFrame`.
    public static let slotCount = 33

    public let header: LIPHeader
    public let keys: [LIPKey]
    public let duplicateValueCount: Int
    public let markerCount: Int
    public let unmappedKeyCount: Int

    public init(data: Data) throws {
        do {
            self = try LIPDecoder(data: data).decode()
        } catch let error as LIPError {
            throw error
        } catch {
            throw LIPError.malformed(String(describing: error))
        }
    }

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

    public var duration: Double {
        Double(header.firstFrame + header.frameCount) / Self.framesPerSecond
    }

    public func sample(at seconds: Double) -> LIPSample {
        let safeSeconds = seconds.isFinite ? max(0, seconds) : 0
        let frame = safeSeconds * Self.framesPerSecond - Double(header.firstFrame)
        let maximumFrame = Double(max(0, header.frameCount - 1))
        let clampedFrame = min(max(frame, 0), maximumFrame)
        let grouped = Dictionary(grouping: keys, by: \.slot)
        let weights = grouped.mapValues { Self.sample($0, at: clampedFrame) }
        return LIPSample(weightsBySlot: weights)
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
        static let minimumHeaderSize = 24
        static let version: UInt32 = 1
        /// Ticks per slot. The duration field is the slot budget in ticks plus
        /// `durationBias`, which is what makes the stride readable.
        static let ticksPerSlot = 4
        static let durationBias: UInt32 = 28
        /// The extra bytes the alternate header family carries before the tuple
        /// width. One and three are the observed values; the range is the
        /// search window, not a claim about what may appear in it.
        static let tupleWidthSearch = 0 ... 8
        static let maximumTupleWidth = 3
        static let maximumTargetCount = 64
    }

    private let bytes: [UInt8]

    init(data: Data) {
        bytes = [UInt8](data)
    }

    func decode() throws -> LIPFile {
        let header = try readHeader()
        let decoded = try readKeys(header: header)
        return LIPFile(
            header: header,
            keys: decoded.keys,
            duplicateValueCount: decoded.duplicates,
            markerCount: decoded.markers,
            unmappedKeyCount: decoded.keys.count {
                !LipVisemeMapping.mappedSlots.contains($0.slot)
            }
        )
    }

    // MARK: - Header

    private func readHeader() throws -> LIPHeader {
        guard bytes.count >= Layout.minimumHeaderSize else {
            throw LIPError.malformed("file is shorter than the 24-byte header")
        }
        let version = uint32(at: 0)
        guard version == Layout.version else {
            throw LIPError.unsupported("animation version \(version)")
        }
        let durationTicks = uint32(at: 4)
        let activeCurveCount = uint32(at: 8)
        let frameCount = Int(uint16(at: 12))
        guard frameCount > 0 else { throw LIPError.malformed("frame count is zero") }
        let slotsPerFrame = try readSlotsPerFrame(
            durationTicks: durationTicks, frameCount: frameCount
        )
        let tail = try readHeaderTail(frameCount: frameCount, slotsPerFrame: slotsPerFrame)
        // Recorded, not validated: many vanilla files declare nine curves
        // against a vocabulary of eight, and nothing indexes by this field.
        return LIPHeader(
            durationTicks: durationTicks,
            activeCurveCount: activeCurveCount,
            frameCount: frameCount,
            firstFrame: tail.firstFrame,
            unknownValue: uint16(at: 22 + tail.shift),
            tupleWidth: tail.tupleWidth,
            targetCount: tail.targetCount,
            slotsPerFrame: slotsPerFrame,
            headerSize: Layout.minimumHeaderSize + tail.shift
        )
    }

    /// `durationTicks == 4 * slotsPerFrame * frameCount + 28`. A file whose
    /// duration does not resolve to a whole stride is not one this decoder can
    /// place on a grid, so it is reported rather than guessed at.
    private func readSlotsPerFrame(durationTicks: UInt32, frameCount: Int) throws -> Int {
        guard durationTicks > Layout.durationBias else {
            throw LIPError.malformed("duration ticks \(durationTicks) below the bias")
        }
        let budget = Int(durationTicks - Layout.durationBias)
        let divisor = Layout.ticksPerSlot * frameCount
        guard budget % divisor == 0 else {
            throw LIPError.unsupported(
                "duration ticks \(durationTicks) imply no whole slot stride "
                    + "for \(frameCount) frames"
            )
        }
        let slotsPerFrame = budget / divisor
        guard slotsPerFrame > 0, slotsPerFrame <= Layout.maximumTargetCount * 2 + 1 else {
            throw LIPError.unsupported("slot stride \(slotsPerFrame)")
        }
        return slotsPerFrame
    }

    private struct HeaderTail {
        let shift: Int
        let tupleWidth: Int
        let firstFrame: Int
        let targetCount: Int
    }

    /// Finds the tuple width, pre-roll and vocabulary, which sit at offset 14,
    /// 16 and 20 in the common case and a few bytes later in the family that
    /// carries extra bytes after the frame count. The stride agreement is what
    /// makes the match a match rather than a coincidence: the vocabulary has to
    /// explain the stride the duration field already fixed.
    private func readHeaderTail(frameCount: Int, slotsPerFrame: Int) throws -> HeaderTail {
        for shift in Layout.tupleWidthSearch {
            guard 24 + shift <= bytes.count else { break }
            let tupleWidth = Int(uint16(at: 14 + shift))
            let firstFrame = Int(Int32(bitPattern: uint32(at: 16 + shift)))
            let targetCount = Int(uint16(at: 20 + shift))
            guard
                tupleWidth >= 1, tupleWidth <= Layout.maximumTupleWidth,
                targetCount >= 1, targetCount <= Layout.maximumTargetCount,
                targetCount * 2 + 1 == slotsPerFrame || targetCount == slotsPerFrame,
                firstFrame <= 0, firstFrame >= -frameCount
            else { continue }
            return HeaderTail(
                shift: shift,
                tupleWidth: tupleWidth,
                firstFrame: firstFrame,
                targetCount: targetCount
            )
        }
        throw LIPError.unsupported(
            "no tuple width, pre-roll and vocabulary consistent with a "
                + "\(slotsPerFrame)-slot stride"
        )
    }

    // MARK: - Payload

    private struct DecodedKeys {
        let keys: [LIPKey]
        let duplicates: Int
        let markers: Int
    }

    /// A token's `00 <tag> 00` suffix can also be the start of the next value, so
    /// each triple is a choice point and the walk backtracks when a reading cannot
    /// reach the end. Multiples of four try the suffix reading first.
    /// One accepted token on the walk: its offset, grid position, branch, and key.
    private struct Frame {
        let offset: Int
        let position: Int
        var branch: Int
        let key: LIPKey?
    }

    private func readKeys(header: LIPHeader) throws -> DecodedKeys {
        let start = header.headerSize
        let slotBudget = header.frameCount * header.slotsPerFrame
        guard bytes.count > start else {
            throw LIPError.malformed("curve payload is empty")
        }
        var visitedDeadEnds = Set<Int>()
        var steps = 0
        var stack = [Frame(offset: start, position: 0, branch: 0, key: nil)]
        while let top = stack.last {
            steps += 1
            guard steps <= Self.stepBudget else {
                throw LIPError.malformed("curve stream did not resolve within the step budget")
            }
            if top.offset == bytes.count {
                return collect(stack, slotsPerFrame: header.slotsPerFrame)
            }
            let step = visitedDeadEnds.contains(top.offset) ? nil
                : nextStep(
                    from: top.offset,
                    position: top.position,
                    branch: top.branch,
                    slotBudget: slotBudget
                )
            guard let step else {
                // Dead ends are remembered by offset, so a blob whose framing is
                // ambiguous in several places still costs one visit per byte
                // offset rather than one per path through them.
                visitedDeadEnds.insert(top.offset)
                stack.removeLast()
                continue
            }
            stack[stack.count - 1].branch += 1
            stack.append(Frame(
                offset: step.offset, position: step.position, branch: 0, key: step.key
            ))
        }
        throw LIPError.malformed("curve stream does not frame to the end of the payload")
    }

    /// The maximum number of walk steps. A blob holds one key per four bytes at
    /// most, so a multiple of the payload length bounds the search without
    /// bounding any real file.
    private static let stepBudget = 1_000_000

    private struct Step {
        let offset: Int
        let position: Int
        let key: LIPKey
    }

    /// The `branch`-th reading of the token at `offset`, or nil when that token
    /// has no further readings.
    private func nextStep(
        from offset: Int, position: Int, branch: Int, slotBudget: Int
    ) -> Step? {
        guard offset + 4 <= bytes.count, position < slotBudget else { return nil }
        let raw = uint32(at: offset)
        let value = Float(bitPattern: raw)
        guard value.isFinite else { return nil }
        var next = offset + 4
        var occupied = 1
        if next + 4 <= bytes.count, uint32(at: next) == raw {
            next += 4
            occupied = 2
        }
        var readings: [(offset: Int, skip: Int)] = [(next, 0)]
        if
            next + 3 <= bytes.count, bytes[next] == 0, bytes[next + 2] == 0,
            bytes[next + 1] != 0
        {
            let suffix = (next + 3, Int(bytes[next + 1]) / 4)
            readings = bytes[next + 1].isMultiple(of: 4)
                ? [suffix, readings[0]] : [readings[0], suffix]
        }
        guard branch < readings.count else { return nil }
        let reading = readings[branch]
        let advance = occupied + reading.skip
        guard position + advance <= slotBudget else { return nil }
        return Step(
            offset: reading.offset,
            position: position + advance,
            key: LIPKey(
                frame: 0, slot: 0, value: value, hasDuplicate: occupied == 2
            )
        )
    }

    /// Turns the accepted walk into keys. The stack carries one entry per token
    /// plus the starting entry, and each entry's position is where its key sat
    /// on the flattened grid.
    private func collect(_ stack: [Frame], slotsPerFrame: Int) -> DecodedKeys {
        var keys: [LIPKey] = []
        var duplicates = 0
        var markers = 0
        keys.reserveCapacity(stack.count)
        for (index, entry) in stack.enumerated() {
            guard let key = entry.key else { continue }
            let position = stack[index - 1].position
            keys.append(LIPKey(
                frame: position / slotsPerFrame,
                slot: position % slotsPerFrame,
                value: key.value,
                hasDuplicate: key.hasDuplicate
            ))
            if key.hasDuplicate {
                duplicates += 1
            }
            let occupied = key.hasDuplicate ? 2 : 1
            if entry.position - position > occupied {
                markers += 1
            }
        }
        return DecodedKeys(keys: keys, duplicates: duplicates, markers: markers)
    }

    // MARK: - Primitives

    private func uint16(at offset: Int) -> UInt16 {
        guard offset >= 0, offset + 2 <= bytes.count else { return 0 }
        return UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    private func uint32(at offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= bytes.count else { return 0 }
        var value: UInt32 = 0
        for index in (0 ..< 4).reversed() {
            value = (value << 8) | UInt32(bytes[offset + index])
        }
        return value
    }
}
