// hkaSplineCompressedAnimation decode tests (todo 6.3) over synthetic in-code
// packfiles only — never extracted game files. Track names/data are invented.
// Byte map: docs/formats/hka-animation.md.

import Foundation
@testable import opensky
import simd
import Testing

private struct HKASplineAnimationFixture {
    var duration: Float = 1
    var quantization: UInt8 = 0x45 // vectors 16-bit, rotations 40-bit
    var descendingKnots = false
    var transformByteCountOverride: Int?
    var omitDataFixup = false

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

private struct HKAAnimationBindingFixture {
    var transformMap: [Int16] = [3, 1]
    var floatMap: [Int16] = [4]

    func build() -> Data {
        var object = [UInt8](repeating: 0, count: 72)
        writeUInt32(UInt32(transformMap.count), at: 0x28, to: &object)
        writeUInt32(UInt32(floatMap.count), at: 0x38, to: &object)
        object[0x40] = 1
        var payload = Data(object)
        let nameOffset = payload.count
        payload.append(Data("TestRig".utf8))
        payload.append(0)
        let transformOffset = payload.count
        for index in transformMap {
            payload.appendUInt16(UInt16(bitPattern: index))
        }
        let floatOffset = payload.count
        for index in floatMap {
            payload.appendUInt16(UInt16(bitPattern: index))
        }

        var fixture = HKXFixture()
        fixture.classNames = [(0x1234_ABCD, "hkaAnimationBinding")]
        fixture.rootClassIndex = 0
        fixture.rootObjectDataOffset = nil
        fixture.payloadOverride = payload
        fixture.dataPayloadSize = payload.count
        fixture.localFixups = [
            .init(from: 0x10, toOffset: UInt32(nameOffset)),
            .init(from: 0x20, toOffset: UInt32(transformOffset)),
            .init(from: 0x30, toOffset: UInt32(floatOffset))
        ]
        fixture.globalFixups = [.init(from: 0x18, toSection: 2, toOffset: 0)]
        fixture.virtualFixups = [.init(
            dataOffset: 0,
            classNameSection: 0,
            classNameOffset: UInt32(fixture.nameOffset(ofClass: 0))
        )]
        return fixture.build()
    }

    private func writeUInt32(_ value: UInt32, at offset: Int, to bytes: inout [UInt8]) {
        bytes[offset] = UInt8(value & 0xFF)
        bytes[offset + 1] = UInt8((value >> 8) & 0xFF)
        bytes[offset + 2] = UInt8((value >> 16) & 0xFF)
        bytes[offset + 3] = UInt8((value >> 24) & 0xFF)
    }
}

struct HKASplineAnimationTests {
    private func firstAnimation(
        _ fixture: HKASplineAnimationFixture
    ) throws -> HKASplineCompressedAnimation {
        let animations = try HKASplineCompressedAnimation.animations(
            in: HKXFile(data: fixture.build())
        )
        #expect(animations.count == 1)
        return try #require(animations.first)
    }

    private func animationError(
        _ fixture: HKASplineAnimationFixture
    ) -> HKASplineAnimationError? {
        do {
            _ = try firstAnimation(fixture)
            return nil
        } catch let error as HKASplineAnimationError {
            return error
        } catch {
            return nil
        }
    }

    @Test func decodesAndSamplesLocalTransforms() throws {
        let animation = try firstAnimation(HKASplineAnimationFixture())
        #expect(animation.duration == 1)
        #expect(animation.frameCount == 31)
        #expect(animation.blockCount == 1)
        #expect(animation.transformTrackCount == 1)

        let start = try #require(animation.localTransforms(at: 0).first)
        #expect(start.translation == SIMD3<Float>(0, 5, 0))
        #expect(start.rotation.vector == SIMD4<Float>(0, 0, 0, 1))
        #expect(start.scale == SIMD3<Float>(2, 3, 4))

        let middle = try #require(animation.localTransforms(at: 0.5).first)
        #expect(abs(middle.translation.x - 15) < 0.001)
        let end = try #require(animation.localTransforms(at: 1).first)
        #expect(abs(end.translation.x - 30) < 0.001)
    }

    @Test func clampsSampleTimeToClip() throws {
        let animation = try firstAnimation(HKASplineAnimationFixture())
        #expect(try animation.localTransforms(at: -10).first?.translation.x == 0)
        let end = try #require(animation.localTransforms(at: 10).first)
        #expect(abs(end.translation.x - 30) < 0.001)
    }

    @Test func fullDurationSamplesStayFiniteAndBounded() throws {
        let animation = try firstAnimation(HKASplineAnimationFixture())
        for frame in 0 ... 30 {
            let pose = try #require(
                animation.localTransforms(at: Float(frame) / 30).first
            )
            let lanes = [
                pose.translation.x, pose.translation.y, pose.translation.z,
                pose.rotation.vector.x, pose.rotation.vector.y,
                pose.rotation.vector.z, pose.rotation.vector.w,
                pose.scale.x, pose.scale.y, pose.scale.z
            ]
            #expect(lanes.allSatisfy { $0.isFinite && abs($0) < 100 })
        }
    }

    @Test func bindsTrackSamplesToBoneIndices() throws {
        let animation = try firstAnimation(HKASplineAnimationFixture())
        let identityBinding = HKAAnimationBinding(
            originalSkeletonName: "TestRig",
            animationTarget: nil,
            transformTrackToBoneIndices: [],
            floatTrackToSlotIndices: [],
            blendHint: 0
        )
        let identity = try #require(
            animation.boneLocalTransforms(at: 0.5, binding: identityBinding).first
        )
        #expect(identity.boneIndex == 0)

        let explicitBinding = HKAAnimationBinding(
            originalSkeletonName: "TestRig",
            animationTarget: nil,
            transformTrackToBoneIndices: [7],
            floatTrackToSlotIndices: [],
            blendHint: 0
        )
        let explicit = try #require(
            animation.boneLocalTransforms(at: 0.5, binding: explicitBinding).first
        )
        #expect(explicit.boneIndex == 7)
        #expect(abs(explicit.pose.translation.x - 15) < 0.001)
    }

    @Test func decodesAnimationBinding() throws {
        let file = try HKXFile(data: HKAAnimationBindingFixture().build())
        let binding = try #require(HKAAnimationBinding.bindings(in: file).first)
        #expect(binding.originalSkeletonName == "TestRig")
        #expect(binding.animationTarget == HKXPointerTarget(sectionIndex: 2, dataOffset: 0))
        #expect(binding.transformTrackToBoneIndices == [3, 1])
        #expect(binding.floatTrackToSlotIndices == [4])
        #expect(binding.blendHint == 1)
    }

    @Test func rejectsBindingCountMismatch() throws {
        let binding = HKAAnimationBinding(
            originalSkeletonName: nil,
            animationTarget: nil,
            transformTrackToBoneIndices: [0, 1],
            floatTrackToSlotIndices: [],
            blendHint: 0
        )
        #expect(throws: HKASplineAnimationError.countMismatch(
            field: "m_transformTrackToBoneIndices", expected: 1, actual: 2
        )) {
            _ = try binding.boneIndices(transformTrackCount: 1)
        }
    }

    @Test func rejectsUnsupportedRotationQuantization() {
        var fixture = HKASplineAnimationFixture()
        fixture.quantization = 0x49 // rotation enum code 4 (48-bit), not probe-verified
        #expect(animationError(fixture) == .unsupportedQuantization(
            trackIndex: 0, component: "rotation", code: 4
        ))
    }

    @Test func rejectsDescendingKnots() throws {
        var fixture = HKASplineAnimationFixture()
        fixture.descendingKnots = true
        let error = try #require(animationError(fixture))
        guard case .invalidSpline(trackIndex: 0, component: "translation", _) = error else {
            Issue.record("expected translation invalidSpline, got \(error)")
            return
        }
    }

    @Test func rejectsTransformBlockSizeMismatch() {
        var fixture = HKASplineAnimationFixture()
        fixture.transformByteCountOverride = 64
        #expect(animationError(fixture) == .blockSizeMismatch(
            blockIndex: 0, expected: 64, consumed: 60
        ))
    }

    @Test func rejectsMissingDataFixup() {
        var fixture = HKASplineAnimationFixture()
        fixture.omitDataFixup = true
        #expect(animationError(fixture) == .missingArrayData(field: "m_data", count: 60))
    }

    @Test func rejectsNonFiniteDuration() throws {
        var fixture = HKASplineAnimationFixture()
        fixture.duration = .nan
        let error = try #require(animationError(fixture))
        guard case .invalidMetadata(field: "m_duration", _) = error else {
            Issue.record("expected invalid duration metadata, got \(error)")
            return
        }
    }
}
