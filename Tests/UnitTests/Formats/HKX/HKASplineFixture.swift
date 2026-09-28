// The synthetic spline-animation packfile every clip-sampling test builds on
// (todo 6.3, reused by issue #187). Invented bytes only: one linear
// translation track, an identity rotation spline, and static scale, laid out
// the way hkaSplineCompressedAnimation reads them. Nothing here is extracted
// from a game file (AGENTS.md "Legal & IP boundary").
//
// Shared rather than private because the behavior evaluator's clip tests need a
// real decoded clip to advance and loop over, not a stand-in.
// Byte map: docs/formats/hka-animation.md.

import Foundation
@testable import opensky

struct HKASplineAnimationFixture {
    var duration: Float = 1
    var quantization: UInt8 = 0x45 // vectors 16-bit, rotations 40-bit
    var descendingKnots = false
    var transformByteCountOverride: Int?
    var omitDataFixup = false
    /// Registers a fixup for `m_extractedMotion`, so the decoded animation
    /// reports `carriesExtractedMotion`. What it points at is a placeholder:
    /// the parser reads the presence of the pointer and never follows it.
    var carriesExtractedMotion = false
    /// Annotation tracks, each a track name and its `(time, text)` marks, laid
    /// out at `hkaAnimation.m_annotationTracks`. Vanilla puts the footstep tags
    /// here rather than in the behavior file's clip triggers.
    var annotationTracks: [(name: String, annotations: [(time: Float, text: String)])] = []

    private static let objectSize = 176

    func build() -> Data {
        var block = blockData()
        let transformByteCount = transformByteCountOverride ?? block.count
        if transformByteCount > block.count {
            block.append(Data(repeating: 0, count: transformByteCount - block.count))
        }
        var payload = objectHeader(dataByteCount: block.count)
        let blockOffsetsOffset = payload.count
        payload.appendUInt32(0)
        let floatBlockOffsetsOffset = payload.count
        payload.appendUInt32(UInt32(transformByteCount))
        let dataOffset = payload.count
        payload.append(block)
        let referenceFrameOffset = payload.count
        if carriesExtractedMotion {
            payload.append(Data(repeating: 0, count: 16))
        }
        let annotationFixups = appendAnnotationTracks(to: &payload)

        var fixture = HKXFixture()
        fixture.classNames = [(0x1234_ABCD, "hkaSplineCompressedAnimation")]
        fixture.rootClassIndex = 0
        fixture.rootObjectDataOffset = nil
        fixture.globalFixups = []
        fixture.payloadOverride = payload
        fixture.dataPayloadSize = payload.count
        fixture.localFixups = [
            .init(from: 0x58, toOffset: UInt32(blockOffsetsOffset)),
            .init(from: 0x68, toOffset: UInt32(floatBlockOffsetsOffset))
        ]
        if !omitDataFixup {
            fixture.localFixups.append(.init(from: 0x98, toOffset: UInt32(dataOffset)))
        }
        if carriesExtractedMotion {
            fixture.localFixups.append(
                .init(from: 0x20, toOffset: UInt32(referenceFrameOffset))
            )
        }
        fixture.localFixups.append(contentsOf: annotationFixups)
        fixture.virtualFixups = [.init(
            dataOffset: 0,
            classNameSection: 0,
            classNameOffset: UInt32(fixture.nameOffset(ofClass: 0))
        )]
        return fixture.build()
    }

    private func objectHeader(dataByteCount: Int) -> Data {
        var object = [UInt8](repeating: 0, count: Self.objectSize)
        writeUInt32(5, at: 0x10, to: &object) // hkaAnimation::HK_SPLINE_COMPRESSED_ANIMATION
        writeFloat(duration, at: 0x14, to: &object)
        writeUInt32(1, at: 0x18, to: &object) // transform tracks
        writeUInt32(0, at: 0x1C, to: &object) // float tracks
        writeUInt32(UInt32(annotationTracks.count), at: 0x30, to: &object) // m_annotationTracks
        writeUInt32(31, at: 0x38, to: &object) // frames 0 ... 30
        writeUInt32(1, at: 0x3C, to: &object)
        writeUInt32(256, at: 0x40, to: &object)
        writeUInt32(4, at: 0x44, to: &object) // one 4-byte transform mask
        writeFloat(8.5, at: 0x48, to: &object)
        writeFloat(1 / 8.5, at: 0x4C, to: &object)
        writeFloat(1 / 30, at: 0x50, to: &object)
        writeUInt32(1, at: 0x60, to: &object) // blockOffsets hkArray size
        writeUInt32(1, at: 0x70, to: &object) // floatBlockOffsets hkArray size
        writeUInt32(UInt32(dataByteCount), at: 0xA0, to: &object) // data hkArray size
        return Data(object)
    }

    /// Lays out `m_annotationTracks` behind the object: the fixed-stride track
    /// records, then each track's annotation records, then the strings both
    /// point at. Answers with the local fixups that wire them together, which
    /// the caller adds to the ones the block tables already need.
    private func appendAnnotationTracks(to payload: inout Data) -> [HKXFixture.LocalFixup] {
        guard !annotationTracks.isEmpty else { return [] }
        while payload.count % 16 != 0 {
            payload.append(0)
        }
        let base = payload.count
        var layout = AnnotationLayout(
            base: base,
            trackCount: annotationTracks.count,
            annotationCounts: annotationTracks.map(\.annotations.count)
        )
        var fixups: [HKXFixture.LocalFixup] = [
            .init(from: 0x28, toOffset: UInt32(base))
        ]
        var tracks = [UInt8](repeating: 0, count: Self.trackStride * annotationTracks.count)
        var annotations = [UInt8]()
        for (index, track) in annotationTracks.enumerated() {
            let record = index * Self.trackStride
            fixups.append(.init(
                from: UInt32(base + record), toOffset: UInt32(layout.offset(of: track.name))
            ))
            if !track.annotations.isEmpty {
                fixups.append(.init(
                    from: UInt32(base + record + 0x08),
                    toOffset: UInt32(layout.annotationOffsets[index])
                ))
            }
            writeUInt32(UInt32(track.annotations.count), at: record + 0x10, to: &tracks)
            for (position, annotation) in track.annotations.enumerated() {
                var element = [UInt8](repeating: 0, count: Self.annotationStride)
                writeFloat(annotation.time, at: 0x00, to: &element)
                annotations.append(contentsOf: element)
                let at = layout.annotationOffsets[index] + position * Self.annotationStride
                fixups.append(.init(
                    from: UInt32(at + 0x08), toOffset: UInt32(layout.offset(of: annotation.text))
                ))
            }
        }
        payload.append(contentsOf: tracks)
        payload.append(contentsOf: annotations)
        payload.append(layout.strings)
        return fixups
    }

    /// `hkaAnnotationTrack` and its `Annotation` element, whose strides the
    /// parser's own byte map records.
    private static let trackStride = 24
    private static let annotationStride = 16

    /// Where each part of the annotation region lands, and the string blob the
    /// pointers resolve into. Strings are pooled, so a track and an annotation
    /// spelled the same share one null-terminated copy.
    private struct AnnotationLayout {
        let annotationOffsets: [Int]
        private(set) var strings = Data()
        private let stringBase: Int
        private var offsetByText: [String: Int] = [:]

        init(base: Int, trackCount: Int, annotationCounts: [Int]) {
            var cursor = base + HKASplineAnimationFixture.trackStride * trackCount
            var offsets: [Int] = []
            for count in annotationCounts {
                offsets.append(cursor)
                cursor += HKASplineAnimationFixture.annotationStride * count
            }
            annotationOffsets = offsets
            stringBase = cursor
        }

        mutating func offset(of text: String) -> Int {
            if let known = offsetByText[text] {
                return known
            }
            let at = stringBase + strings.count
            offsetByText[text] = at
            strings.append(Data(text.utf8))
            strings.append(0)
            return at
        }
    }

    /// One linear translation.x spline, static translation.y, identity z;
    /// identity quaternion spline; three static scale lanes.
    private func blockData() -> Data {
        var block = Data([quantization, 0x12, 0xF0, 0x07])

        appendSplineHeader(to: &block) // translation
        align(&block, to: 4)
        block.appendFloat32(0) // dynamic x minimum
        block.appendFloat32(30) // dynamic x maximum
        block.appendFloat32(5) // static y
        block.appendUInt16(0)
        block.appendUInt16(UInt16.max)
        align(&block, to: 4)

        appendSplineHeader(to: &block) // rotation
        appendQuaternion40Identity(to: &block)
        appendQuaternion40Identity(to: &block)
        align(&block, to: 4)

        block.appendFloat32(2)
        block.appendFloat32(3)
        block.appendFloat32(4)
        return block
    }

    private func appendSplineHeader(to data: inout Data) {
        data.appendUInt16(1) // stored items -> two control points
        data.append(1) // linear
        data.append(contentsOf: descendingKnots ? [0, 30, 0, 30] : [0, 0, 30, 30])
    }

    private func appendQuaternion40Identity(to data: inout Data) {
        let bits = UInt64(0x7FF)
            | UInt64(0x7FF) << 12
            | UInt64(0x7FF) << 24
            | UInt64(3) << 36 // omitted-largest lane = w
        for index in 0 ..< 5 {
            data.append(UInt8((bits >> UInt64(index * 8)) & 0xFF))
        }
    }

    private func align(_ data: inout Data, to alignment: Int) {
        while data.count % alignment != 0 {
            data.append(0)
        }
    }

    private func writeUInt32(_ value: UInt32, at offset: Int, to bytes: inout [UInt8]) {
        bytes[offset] = UInt8(value & 0xFF)
        bytes[offset + 1] = UInt8((value >> 8) & 0xFF)
        bytes[offset + 2] = UInt8((value >> 16) & 0xFF)
        bytes[offset + 3] = UInt8((value >> 24) & 0xFF)
    }

    private func writeFloat(_ value: Float, at offset: Int, to bytes: inout [UInt8]) {
        writeUInt32(value.bitPattern, at: offset, to: &bytes)
    }
}
