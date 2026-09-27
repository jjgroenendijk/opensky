// hkaSplineCompressedAnimation decode tests (todo 6.3) over synthetic in-code
// packfiles only — never extracted game files. Track names/data are invented.
// The packfile builder lives in HKASplineFixture.swift, because the behavior
// evaluator tests (issue #187) need the same synthetic clip.
// Byte map: docs/formats/hka-animation.md.

import Foundation
@testable import opensky
import simd
import Testing

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

    /// `m_extractedMotion` at 0x20 is read for presence only: null means the
    /// clip animates in place, a fixup means it carries authored travel. The
    /// distinction is what decides whether the clip may drive the character
    /// (issue #370).
    @Test func readsWhetherTheClipCarriesExtractedMotion() throws {
        #expect(try !firstAnimation(HKASplineAnimationFixture()).carriesExtractedMotion)
        var withReferenceFrame = HKASplineAnimationFixture()
        withReferenceFrame.carriesExtractedMotion = true
        #expect(try firstAnimation(withReferenceFrame).carriesExtractedMotion)
    }

    /// `m_annotationTracks` at 0x28 is where Skyrim's footstep tags live: the
    /// locomotion clip generators in `mt_behavior.hkx` carry an empty
    /// `m_triggers`, so an animation whose annotations are dropped can never
    /// fire `FootLeft` (issues #385, #394).
    @Test func readsAnnotationTracksAndTheirMarks() throws {
        var fixture = HKASplineAnimationFixture()
        fixture.annotationTracks = [
            (name: "NPC Root [Root]", annotations: [
                (time: 0.8, text: "FootRight"), (time: 0.25, text: "FootLeft")
            ]),
            (name: "NPC Spine [Spn0]", annotations: [])
        ]
        let animation = try firstAnimation(fixture)

        #expect(animation.annotationTracks.count == 2)
        #expect(animation.annotationTracks.first?.name == "NPC Root [Root]")
        #expect(animation.annotationTracks.last?.annotations.isEmpty == true)
        // `annotations` merges every track and sorts by time, because Havok
        // exports one track per transform track and the consumer wants the
        // clip's marks in the order playback reaches them.
        #expect(animation.annotations == [
            HKAAnnotation(time: 0.25, text: "FootLeft"),
            HKAAnnotation(time: 0.8, text: "FootRight")
        ])
    }

    /// An animation with no annotation tracks is the ordinary case, and the
    /// null array it writes must not be read as an unresolved reference.
    @Test func anUnannotatedAnimationDecodesWithNoMarks() throws {
        #expect(try firstAnimation(HKASplineAnimationFixture()).annotations.isEmpty)
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
