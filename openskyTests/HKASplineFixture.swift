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
