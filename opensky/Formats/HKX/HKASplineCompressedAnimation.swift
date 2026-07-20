// hkaSplineCompressedAnimation object decode (todo 6.3): metadata + block
// tables + per-track local-transform sampling. Object layout comes from
// hkxparse (MIT) + HKX2Library (MIT); spline block grammar + quantization
// comes from PredatorCZ/HavokLib (GPLv3), independently reimplemented here.
// Every field/block boundary was probe-verified against Skyrim SE's male
// mt_idle.hkx (hk_2010.2.0-r1, 64-bit LE). No Havok SDK or Bethesda code
// consulted. Full byte map + citations: docs/formats/hka-animation.md.

import Foundation
import simd

nonisolated enum HKASplineAnimationError: Error, Equatable {
    case invalidMetadata(field: String, value: String)
    case missingArrayData(field: String, count: Int)
    case arrayOutOfBounds(field: String, offset: Int, needed: Int, available: Int)
    case countMismatch(field: String, expected: Int, actual: Int)
    case blockOutOfBounds(blockIndex: Int, offset: Int, limit: Int)
    case blockSizeMismatch(blockIndex: Int, expected: Int, consumed: Int)
    case unsupportedQuantization(trackIndex: Int, component: String, code: Int)
    case invalidSpline(trackIndex: Int, component: String, reason: String)
    case invalidBoneIndex(trackIndex: Int, boneIndex: Int)
    case nonFiniteTransform(trackIndex: Int)
}

nonisolated struct HKABoneTransformSample {
    let boneIndex: Int
    let pose: HKABonePose
}

/// Decoded spline clip. `localTransforms` preserves transform-track order;
/// `boneLocalTransforms` resolves that order through hkaAnimationBinding.
nonisolated struct HKASplineCompressedAnimation {
    let objectSectionIndex: Int
    let objectDataOffset: Int
    let duration: Float
    let frameDuration: Float
    let frameCount: Int
    let maxFramesPerBlock: Int
    let transformTrackCount: Int
    let floatTrackCount: Int
    let blocks: [HKASplineBlock]

    var blockCount: Int {
        blocks.count
    }

    static let className = "hkaSplineCompressedAnimation"

    /// Every spline-compressed animation object in inventory order.
    static func animations(in file: HKXFile) throws -> [HKASplineCompressedAnimation] {
        var result: [HKASplineCompressedAnimation] = []
        for object in file.objects where object.className == className {
            guard file.sections.indices.contains(object.sectionIndex) else { continue }
            let payload = try file.sectionData(at: object.sectionIndex)
            let fixups = file.sections[object.sectionIndex].localFixups
            try result.append(HKASplineObjectDecoder.decode(
                payload: payload,
                base: object.dataOffset,
                sectionIndex: object.sectionIndex,
                localFixups: fixups
            ))
        }
        return result
    }

    /// Samples every transform track at seconds from clip start. Time clamps
    /// to [0, duration], including exact final-frame sampling.
    func localTransforms(at time: Float) throws -> [HKABonePose] {
        guard time.isFinite else {
            throw HKASplineAnimationError.invalidMetadata(
                field: "sample time", value: String(describing: time)
            )
        }
        let clampedTime = min(max(time, 0), duration)
        let blockDuration = Float(maxFramesPerBlock - 1) * frameDuration
        var blockIndex = Int(clampedTime / blockDuration)
        blockIndex = min(max(blockIndex, 0), blocks.count - 1)
        let localTime = clampedTime - Float(blockIndex) * blockDuration
        let localFrame = max(localTime / frameDuration, 0)
        let poses = try blocks[blockIndex].localTransforms(at: localFrame)
        guard poses.count == transformTrackCount else {
            throw HKASplineAnimationError.countMismatch(
                field: "sample transform tracks",
                expected: transformTrackCount,
                actual: poses.count
            )
        }
        return poses
    }

    /// Resolves transform-track order through hkaAnimationBinding. Empty
    /// mapping means identity, as in Skyrim's mt_idle clip.
    func boneLocalTransforms(
        at time: Float,
        binding: HKAAnimationBinding
    ) throws -> [HKABoneTransformSample] {
        let poses = try localTransforms(at: time)
        let boneIndices = try binding.boneIndices(transformTrackCount: poses.count)
        return zip(boneIndices, poses).map {
            HKABoneTransformSample(boneIndex: $0.0, pose: $0.1)
        }
    }
}

nonisolated private struct HKASplineMetadata {
    let duration: Float
    let frameDuration: Float
    let frameCount: Int
    let blockCount: Int
    let maxFramesPerBlock: Int
    let transformTrackCount: Int
    let floatTrackCount: Int
    let maskSize: Int
    let storedBlockDuration: Float
    let blockInverseDuration: Float
    let endian: Int
}

nonisolated private struct HKASplineTables {
    let blockOffsets: [UInt32]
    let floatBlockOffsets: [UInt32]
    let bytes: Data
}

nonisolated private enum HKASplineObjectDecoder {
    private static let animationTypeField = 0x10
    private static let durationField = 0x14
    private static let transformTrackCountField = 0x18
    private static let floatTrackCountField = 0x1C
    private static let frameCountField = 0x38
    private static let blockCountField = 0x3C
    private static let maxFramesPerBlockField = 0x40
    private static let maskAndQuantizationSizeField = 0x44
    private static let blockDurationField = 0x48
    private static let blockInverseDurationField = 0x4C
    private static let frameDurationField = 0x50
    private static let blockOffsetsField = 0x58
    private static let floatBlockOffsetsField = 0x68
    private static let transformOffsetsField = 0x78
    private static let floatOffsetsField = 0x88
    private static let dataField = 0x98
    private static let endianField = 0xA8

    static func decode(
        payload: Data,
        base: Int,
        sectionIndex: Int,
        localFixups: [HKXLocalFixup]
    ) throws -> HKASplineCompressedAnimation {
        let fixups = Dictionary(
            localFixups.map { ($0.fromOffset, $0.toOffset) },
            uniquingKeysWith: { first, _ in first }
        )
        let metadata = try readMetadata(payload, base: base)
        try validate(metadata)
        let tables = try readTables(payload, base: base, fixups: fixups)
        guard tables.blockOffsets.count == metadata.blockCount else {
            throw mismatch(
                "m_blockOffsets", metadata.blockCount, tables.blockOffsets.count
            )
        }
        guard tables.floatBlockOffsets.count == metadata.blockCount else {
            throw mismatch(
                "m_floatBlockOffsets", metadata.blockCount, tables.floatBlockOffsets.count
            )
        }
        return try HKASplineCompressedAnimation(
            objectSectionIndex: sectionIndex,
            objectDataOffset: base,
            duration: metadata.duration,
            frameDuration: metadata.frameDuration,
            frameCount: metadata.frameCount,
            maxFramesPerBlock: metadata.maxFramesPerBlock,
            transformTrackCount: metadata.transformTrackCount,
            floatTrackCount: metadata.floatTrackCount,
            blocks: decodeBlocks(metadata: metadata, tables: tables)
        )
    }

    private static func readMetadata(_ data: Data, base: Int) throws -> HKASplineMetadata {
        let animationType = try readInt(data, at: base + animationTypeField)
        guard animationType == 5 else { throw invalid("m_type", animationType) }
        return try HKASplineMetadata(
            duration: readFloat(data, at: base + durationField),
            frameDuration: readFloat(data, at: base + frameDurationField),
            frameCount: readInt(data, at: base + frameCountField),
            blockCount: readInt(data, at: base + blockCountField),
            maxFramesPerBlock: readInt(data, at: base + maxFramesPerBlockField),
            transformTrackCount: readInt(data, at: base + transformTrackCountField),
            floatTrackCount: readInt(data, at: base + floatTrackCountField),
            maskSize: readInt(data, at: base + maskAndQuantizationSizeField),
            storedBlockDuration: readFloat(data, at: base + blockDurationField),
            blockInverseDuration: readFloat(data, at: base + blockInverseDurationField),
            endian: readInt(data, at: base + endianField)
        )
    }

    private static func validate(_ metadata: HKASplineMetadata) throws {
        guard metadata.duration.isFinite, metadata.duration >= 0 else {
            throw invalid("m_duration", metadata.duration)
        }
        guard metadata.frameDuration.isFinite, metadata.frameDuration > 0 else {
            throw invalid("m_frameDuration", metadata.frameDuration)
        }
        guard metadata.frameCount > 0 else { throw invalid("m_numFrames", metadata.frameCount) }
        guard metadata.blockCount > 0 else { throw invalid("m_numBlocks", metadata.blockCount) }
        guard metadata.maxFramesPerBlock > 1 else {
            throw invalid("m_maxFramesPerBlock", metadata.maxFramesPerBlock)
        }
        guard metadata.transformTrackCount > 0 else {
            throw invalid("m_numberOfTransformTracks", metadata.transformTrackCount)
        }
        guard metadata.floatTrackCount >= 0 else {
            throw invalid("m_numberOfFloatTracks", metadata.floatTrackCount)
        }
        let expectedMaskSize = metadata.transformTrackCount * 4 + metadata.floatTrackCount
        guard metadata.maskSize == expectedMaskSize else {
            throw mismatch("m_maskAndQuantizationSize", expectedMaskSize, metadata.maskSize)
        }
        let expectedBlockDuration = Float(metadata.maxFramesPerBlock - 1)
            * metadata.frameDuration
        guard
            metadata.storedBlockDuration.isFinite,
            abs(metadata.storedBlockDuration - expectedBlockDuration) < 0.001
        else {
            throw invalid("m_blockDuration", metadata.storedBlockDuration)
        }
        guard
            metadata.blockInverseDuration.isFinite,
            abs(metadata.blockInverseDuration * metadata.storedBlockDuration - 1) < 0.001
        else {
            throw invalid("m_blockInverseDuration", metadata.blockInverseDuration)
        }
        guard metadata.endian == 0 else { throw invalid("m_endian", metadata.endian) }
    }

    private static func readTables(
        _ payload: Data,
        base: Int,
        fixups: [Int: Int]
    ) throws -> HKASplineTables {
        let blockOffsets = try readUInt32Array(
            payload, base: base, field: blockOffsetsField,
            fixups: fixups, name: "m_blockOffsets"
        )
        let floatBlockOffsets = try readUInt32Array(
            payload, base: base, field: floatBlockOffsetsField,
            fixups: fixups, name: "m_floatBlockOffsets"
        )
        _ = try readUInt32Array(
            payload, base: base, field: transformOffsetsField,
            fixups: fixups, name: "m_transformOffsets"
        )
        _ = try readUInt32Array(
            payload, base: base, field: floatOffsetsField,
            fixups: fixups, name: "m_floatOffsets"
        )
        return try HKASplineTables(
            blockOffsets: blockOffsets,
            floatBlockOffsets: floatBlockOffsets,
            bytes: readByteArray(
                payload, base: base, field: dataField, fixups: fixups, name: "m_data"
            )
        )
    }

    private static func decodeBlocks(
        metadata: HKASplineMetadata,
        tables: HKASplineTables
    ) throws -> [HKASplineBlock] {
        var blocks: [HKASplineBlock] = []
        blocks.reserveCapacity(metadata.blockCount)
        for blockIndex in 0 ..< metadata.blockCount {
            let start = Int(tables.blockOffsets[blockIndex])
            let end = blockIndex + 1 < metadata.blockCount
                ? Int(tables.blockOffsets[blockIndex + 1])
                : tables.bytes.count
            let layout = HKASplineBlockLayout(
                blockIndex: blockIndex,
                start: start,
                end: end,
                transformByteCount: Int(tables.floatBlockOffsets[blockIndex]),
                transformTrackCount: metadata.transformTrackCount,
                floatTrackCount: metadata.floatTrackCount
            )
            try blocks.append(HKASplineBlock.decode(data: tables.bytes, layout: layout))
        }
        return blocks
    }

    private static func readUInt32Array(
        _ payload: Data,
        base: Int,
        field: Int,
        fixups: [Int: Int],
        name: String
    ) throws -> [UInt32] {
        let (count, offset) = try arrayDescriptor(
            payload, base: base, field: field, fixups: fixups, name: name
        )
        guard count > 0 else { return [] }
        guard let offset else {
            throw HKASplineAnimationError.missingArrayData(field: name, count: count)
        }
        try requireBounds(offset, count * 4, payload.count, field: name)
        var reader = BinaryReader(payload, offset: offset)
        return try (0 ..< count).map { _ in try reader.readUInt32() }
    }

    private static func readByteArray(
        _ payload: Data,
        base: Int,
        field: Int,
        fixups: [Int: Int],
        name: String
    ) throws -> Data {
        let (count, offset) = try arrayDescriptor(
            payload, base: base, field: field, fixups: fixups, name: name
        )
        guard count > 0 else { return Data() }
        guard let offset else {
            throw HKASplineAnimationError.missingArrayData(field: name, count: count)
        }
        try requireBounds(offset, count, payload.count, field: name)
        var reader = BinaryReader(payload, offset: offset)
        return try reader.read(count: count)
    }

    private static func arrayDescriptor(
        _ payload: Data,
        base: Int,
        field: Int,
        fixups: [Int: Int],
        name: String
    ) throws -> (count: Int, offset: Int?) {
        let count = try readInt(payload, at: base + field + 8)
        guard count >= 0 else { throw invalid(name, count) }
        return (count, fixups[base + field])
    }

    private static func readInt(_ data: Data, at offset: Int) throws -> Int {
        try requireBounds(offset, 4, data.count, field: "object metadata")
        var reader = BinaryReader(data, offset: offset)
        return try Int(Int32(bitPattern: reader.readUInt32()))
    }

    private static func readFloat(_ data: Data, at offset: Int) throws -> Float {
        try requireBounds(offset, 4, data.count, field: "object metadata")
        var reader = BinaryReader(data, offset: offset)
        return try reader.readFloat32()
    }

    private static func requireBounds(
        _ offset: Int,
        _ length: Int,
        _ available: Int,
        field: String
    ) throws {
        guard offset >= 0, length >= 0, offset <= available - length else {
            throw HKASplineAnimationError.arrayOutOfBounds(
                field: field, offset: offset, needed: length, available: available
            )
        }
    }

    private static func invalid(
        _ field: String,
        _ value: some CustomStringConvertible
    ) -> HKASplineAnimationError {
        .invalidMetadata(field: field, value: String(describing: value))
    }

    private static func mismatch(
        _ field: String,
        _ expected: Int,
        _ actual: Int
    ) -> HKASplineAnimationError {
        .countMismatch(field: field, expected: expected, actual: actual)
    }
}
