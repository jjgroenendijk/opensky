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
    /// True when `hkaAnimation.m_extractedMotion` points at an
    /// `hkaAnimatedReferenceFrame`, which is Havok's statement that this clip
    /// carries authored travel rather than animating in place.
    ///
    /// Only the presence is read. The reference frame's own contents are not
    /// decoded, because no file in a vanilla Skyrim SE install carries one:
    /// the flag exists so a consumer can tell an in-place clip from a
    /// root-motion clip without inferring it from how far the root bone
    /// happens to drift. See docs/engine/walk-mode.md.
    let carriesExtractedMotion: Bool
    /// `hkaAnimation.m_annotationTracks`. Havok exports one track per transform
    /// track and vanilla Skyrim leaves all but the first empty, so consumers
    /// read `annotations` rather than indexing this.
    let annotationTracks: [HKAAnnotationTrack]
    let blocks: [HKASplineBlock]

    var blockCount: Int {
        blocks.count
    }

    /// Every annotation of every track, earliest first. This is what carries
    /// the footstep tags: `FootLeft` and `FootRight` are annotations on the
    /// locomotion clips, not triggers on the behavior file's clip generators
    /// (see HKAAnnotationTrack.swift).
    var annotations: [HKAAnnotation] {
        annotationTracks.flatMap(\.annotations).sorted { $0.time < $1.time }
    }

    static let className = "hkaSplineCompressedAnimation"

    /// Every spline-compressed animation object in inventory order.
    static func animations(in file: HKXFile) throws -> [HKASplineCompressedAnimation] {
        let graph = try HKXObjectGraph(file: file)
        var result: [HKASplineCompressedAnimation] = []
        for object in graph.objects(ofClass: className) {
            guard var cursor = graph.cursor(at: object) else { continue }
            try result.append(HKASplineObjectDecoder.decode(cursor: &cursor))
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
    private static let animationTypeField = HKXField(0x10, "m_type")
    private static let durationField = HKXField(0x14, "m_duration")
    private static let transformTrackCountField = HKXField(0x18, "m_numberOfTransformTracks")
    private static let floatTrackCountField = HKXField(0x1C, "m_numberOfFloatTracks")
    private static let extractedMotionField = HKXField(0x20, "m_extractedMotion")
    private static let frameCountField = HKXField(0x38, "m_numFrames")
    private static let blockCountField = HKXField(0x3C, "m_numBlocks")
    private static let maxFramesPerBlockField = HKXField(0x40, "m_maxFramesPerBlock")
    private static let maskAndQuantizationSizeField = HKXField(
        0x44, "m_maskAndQuantizationSize"
    )
    private static let blockDurationField = HKXField(0x48, "m_blockDuration")
    private static let blockInverseDurationField = HKXField(0x4C, "m_blockInverseDuration")
    private static let frameDurationField = HKXField(0x50, "m_frameDuration")
    private static let blockOffsetsField = HKXField(0x58, "m_blockOffsets")
    private static let floatBlockOffsetsField = HKXField(0x68, "m_floatBlockOffsets")
    private static let transformOffsetsField = HKXField(0x78, "m_transformOffsets")
    private static let floatOffsetsField = HKXField(0x88, "m_floatOffsets")
    private static let dataField = HKXField(0x98, "m_data")
    private static let endianField = HKXField(0xA8, "m_endian")

    static func decode(
        cursor: inout HKXObjectCursor
    ) throws -> HKASplineCompressedAnimation {
        let sectionIndex = cursor.sectionIndex
        let base = cursor.base
        let metadata = try readMetadata(cursor: &cursor)
        try validate(metadata)
        // Read through `optionalPointer` because a null here is the ordinary
        // case rather than an unresolved reference: an in-place clip is what
        // every vanilla locomotion animation is.
        let extractedMotion = cursor.optionalPointer(at: extractedMotionField) != nil
        let annotationTracks = HKAAnnotationTrack.tracks(cursor: &cursor)
        let tables = try readTables(cursor: &cursor)
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
            carriesExtractedMotion: extractedMotion,
            annotationTracks: annotationTracks,
            blocks: decodeBlocks(metadata: metadata, tables: tables)
        )
    }

    private static func readMetadata(
        cursor: inout HKXObjectCursor
    ) throws -> HKASplineMetadata {
        let animationType = try readInt(at: animationTypeField, cursor: &cursor)
        guard animationType == 5 else { throw invalid(animationTypeField.name, animationType) }
        return try HKASplineMetadata(
            duration: readFloat(at: durationField, cursor: &cursor),
            frameDuration: readFloat(at: frameDurationField, cursor: &cursor),
            frameCount: readInt(at: frameCountField, cursor: &cursor),
            blockCount: readInt(at: blockCountField, cursor: &cursor),
            maxFramesPerBlock: readInt(at: maxFramesPerBlockField, cursor: &cursor),
            transformTrackCount: readInt(at: transformTrackCountField, cursor: &cursor),
            floatTrackCount: readInt(at: floatTrackCountField, cursor: &cursor),
            maskSize: readInt(at: maskAndQuantizationSizeField, cursor: &cursor),
            storedBlockDuration: readFloat(at: blockDurationField, cursor: &cursor),
            blockInverseDuration: readFloat(at: blockInverseDurationField, cursor: &cursor),
            endian: readInt(at: endianField, cursor: &cursor)
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

    private static func readTables(cursor: inout HKXObjectCursor) throws -> HKASplineTables {
        let blockOffsets = try readUInt32Array(at: blockOffsetsField, cursor: &cursor)
        let floatBlockOffsets = try readUInt32Array(at: floatBlockOffsetsField, cursor: &cursor)
        // Read for their bounds checks: a file whose per-track offset tables do
        // not resolve is malformed even though block decoding does not use them.
        _ = try readUInt32Array(at: transformOffsetsField, cursor: &cursor)
        _ = try readUInt32Array(at: floatOffsetsField, cursor: &cursor)
        return try HKASplineTables(
            blockOffsets: blockOffsets,
            floatBlockOffsets: floatBlockOffsets,
            bytes: readByteArray(at: dataField, cursor: &cursor)
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
        at field: HKXField,
        cursor: inout HKXObjectCursor
    ) throws -> [UInt32] {
        let count = try arrayCount(at: field, cursor: &cursor)
        guard count > 0 else { return [] }
        guard let values = cursor.uint32Array(at: field) else {
            throw HKASplineAnimationError.missingArrayData(field: field.name, count: count)
        }
        return values
    }

    private static func readByteArray(
        at field: HKXField,
        cursor: inout HKXObjectCursor
    ) throws -> Data {
        let count = try arrayCount(at: field, cursor: &cursor)
        guard count > 0 else { return Data() }
        guard let bytes = cursor.byteArray(at: field) else {
            throw HKASplineAnimationError.missingArrayData(field: field.name, count: count)
        }
        return bytes
    }

    private static func arrayCount(
        at field: HKXField,
        cursor: inout HKXObjectCursor
    ) throws -> Int {
        guard let count = cursor.arrayCount(at: field) else {
            throw invalid(field.name, "unreadable")
        }
        return count
    }

    private static func readInt(at field: HKXField, cursor: inout HKXObjectCursor) throws -> Int {
        guard let value = cursor.int32(at: field) else {
            throw outOfBounds(field, cursor)
        }
        return value
    }

    private static func readFloat(
        at field: HKXField,
        cursor: inout HKXObjectCursor
    ) throws -> Float {
        guard let value = cursor.float32(at: field) else {
            throw outOfBounds(field, cursor)
        }
        return value
    }

    private static func outOfBounds(
        _ field: HKXField,
        _ cursor: HKXObjectCursor
    ) -> HKASplineAnimationError {
        .arrayOutOfBounds(
            field: "object metadata",
            offset: cursor.base + field.offset,
            needed: 4,
            available: cursor.payload.count
        )
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
