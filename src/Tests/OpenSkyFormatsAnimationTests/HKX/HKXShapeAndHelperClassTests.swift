// Member-value tests for the collision shapes, the resource tree, the extra
// animation classes, and the character helpers. The offsets are in
// docs/formats/hkx-physics.md; all values are invented.

import Foundation
@testable import OpenSkyFormatsAnimation
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import simd
import Testing

@Suite(.tags(.parser))
struct HKXShapeAndHelperClassTests {
    @Test func convexShapesReadRadiusAndSize() throws {
        let capsule = try decodeHKXObject(HKPCapsuleShape.className, HKPCapsuleShape.decode) {
            $0.setUInt64(0xBEEF, at: 0x10)
            $0.setUInt32(3, at: 0x18)
            $0.setFloat(0.1, at: 0x20)
            $0.setVector4(SIMD4(0, 0, 0, 0), at: 0x30)
            $0.setVector4(SIMD4(0, 0, 2, 0), at: 0x40)
        }
        #expect(capsule.header.shapeType == 3 && capsule.header.radius == 0.1)
        #expect(capsule.header.userData == 0xBEEF)
        #expect(capsule.vertexB == SIMD3(0, 0, 2))

        let box = try decodeHKXObject(HKPBoxShape.className, HKPBoxShape.decode) {
            $0.setFloat(0.05, at: 0x20)
            $0.setVector4(SIMD4(1, 2, 3, 0), at: 0x30)
        }
        #expect(box.halfExtents == SIMD3(1, 2, 3) && box.header.radius == 0.05)
    }

    @Test func transformShapesPlaceTheirChild() throws {
        let translate = try decodeHKXObject(
            HKPConvexTranslateShape.className, HKPConvexTranslateShape.decode,
            extra: [(HKPBoxShape.className, 0x400)]
        ) {
            $0.setPointer(at: 0x30, to: 0x400)
            $0.setVector4(SIMD4(4, 5, 6, 0), at: 0x40)
        }
        #expect(translate.shape.childShape?.dataOffset == 0x400)
        #expect(translate.shape.transform.translation == SIMD3(4, 5, 6))

        let transform = try decodeHKXObject(
            HKPConvexTransformShapeObject.className, HKPConvexTransformShapeObject.decode,
            extra: [(HKPBoxShape.className, 0x400)]
        ) {
            $0.setFloat(0.2, at: 0x20)
            $0.setPointer(at: 0x30, to: 0x400)
            $0.setQuarterTurn(at: 0x40, translation: SIMD3(7, 8, 9))
        }
        #expect(transform.shape.transform.translation == SIMD3(7, 8, 9))
        #expect(transform.shape.transform.rotation.columns.0 == SIMD3(0, 1, 0))
        #expect(transform.shape.header.radius == 0.2)
    }

    @Test func convexHullReadsTransposedVerticesAndPlanes() throws {
        let hull = try decodeHKXObject(
            HKPConvexVerticesShape.className, HKPConvexVerticesShape.decode,
            extra: [(HKPConvexVerticesConnectivity.className, 0x800)]
        ) {
            $0.setFloat(0.3, at: 0x20)
            $0.setVector4(SIMD4(1, 1, 1, 0), at: 0x30)
            $0.setVector4(SIMD4(0, 0, 4, 0), at: 0x40)
            $0.setArray(at: 0x50, count: 2, dataOffset: 0x400)
            $0.setVector4(SIMD4(1, 2, 3, 4), at: 0x400)
            $0.setVector4(SIMD4(5, 6, 7, 8), at: 0x410)
            $0.setVector4(SIMD4(9, 10, 11, 12), at: 0x420)
            $0.setVector4(SIMD4(13, 0, 0, 0), at: 0x430)
            $0.setVector4(SIMD4(14, 0, 0, 0), at: 0x440)
            $0.setVector4(SIMD4(15, 0, 0, 0), at: 0x450)
            $0.setInt32(5, at: 0x60)
            $0.setArray(at: 0x78, count: 1, dataOffset: 0x500)
            $0.setVector4(SIMD4(0, 0, 1, -1), at: 0x500)
            $0.setPointer(at: 0x88, to: 0x800)
        }
        #expect(hull.vertices == [
            SIMD3(1, 5, 9), SIMD3(2, 6, 10), SIMD3(3, 7, 11), SIMD3(4, 8, 12), SIMD3(13, 14, 15)
        ])
        #expect(hull.planeEquations == [SIMD4(0, 0, 1, -1)])
        #expect(hull.connectivity?.dataOffset == 0x800)
        #expect(hull.aabbCenter == SIMD3(0, 0, 4) && hull.header.radius == 0.3)

        let faces = try decodeHKXObject(
            HKPConvexVerticesConnectivity.className, HKPConvexVerticesConnectivity.decode
        ) {
            $0.setArray(at: 0x10, count: 3, dataOffset: 0x400)
            for (index, vertex) in [2, 0, 1].enumerated() {
                $0.setInt16(Int16(vertex), at: 0x400 + index * 2)
            }
            $0.setArray(at: 0x20, count: 1, dataOffset: 0x500)
            $0.setUInt8(3, at: 0x500)
        }
        #expect(faces.vertexIndices == [2, 0, 1] && faces.verticesPerFace == [3])
    }

    @Test func listAndMoppShapesPointAtTheirParts() throws {
        let list = try decodeHKXObject(
            HKPListShape.className, HKPListShape.decode,
            extra: [(HKPBoxShape.className, 0x800)]
        ) {
            $0.setArray(at: 0x30, count: 1, dataOffset: 0x400)
            $0.setPointer(at: 0x400, to: 0x800)
            $0.setUInt32(0x2A, at: 0x408)
            $0.setVector4(SIMD4(2, 2, 2, 0), at: 0x50)
            $0.setVector4(SIMD4(0, 1, 0, 0), at: 0x60)
        }
        #expect(list.children.map(\.shape?.dataOffset) == [0x800])
        #expect(list.children.first?.collisionFilterInfo == 0x2A)
        #expect(list.aabbHalfExtents == SIMD3(2, 2, 2) && list.aabbCenter == SIMD3(0, 1, 0))

        let tree = try decodeHKXObject(
            HKPMoppBvTreeShape.className, HKPMoppBvTreeShape.decode,
            extra: [(HKPMoppCode.className, 0x400), (HKPListShape.className, 0x800)]
        ) {
            $0.setPointer(at: 0x28, to: 0x400)
            $0.setPointer(at: 0x58, to: 0x800)
        }
        #expect(tree.code?.dataOffset == 0x400 && tree.childShape?.dataOffset == 0x800)

        let code = try decodeHKXObject(HKPMoppCode.className, HKPMoppCode.decode) {
            $0.setVector4(SIMD4(1, 2, 3, 0.5), at: 0x10)
            $0.setArray(at: 0x20, count: 40, dataOffset: 0x400)
            $0.setUInt8(1, at: 0x30)
        }
        #expect(code.offset == SIMD4(1, 2, 3, 0.5) && code.byteCount == 40 && code.buildType == 1)
    }

    @Test func shapeInfoAndResourceTreeReadTheirNames() throws {
        let info = try decodeHKXObject(
            HKPShapeInfo.className, HKPShapeInfo.decode,
            extra: [(HKPCapsuleShape.className, 0x800)]
        ) {
            $0.setPointer(at: 0x10, to: 0x800)
            $0.setBool(true, at: 0x18)
            $0.setArray(at: 0x20, count: 1, dataOffset: 0x400)
            $0.setString("Head", at: 0x400, storage: 0x500)
            $0.setQuarterTurn(at: 0x40, translation: SIMD3(0, 1, 0))
        }
        #expect(info.shape?.dataOffset == 0x800)
        #expect(info.transform.translation == SIMD3(0, 1, 0))
        #expect(info.isHierarchicalCompound && info.childShapeNames == ["Head"])

        let container = try decodeHKXObject(
            HKMemoryResourceContainer.className, HKMemoryResourceContainer.decode,
            extra: [(HKMemoryResourceHandle.className, 0x800)]
        ) {
            $0.setString("Physics Data", at: 0x10, storage: 0x300)
            $0.setPointerArray(at: 0x20, dataOffset: 0x400, targets: [0x800])
        }
        #expect(container.name == "Physics Data")
        #expect(container.resourceHandles.map { $0?.dataOffset } == [0x800])

        let handle = try decodeHKXObject(
            HKMemoryResourceHandle.className, HKMemoryResourceHandle.decode,
            extra: [(HKPRigidBody.className, 0x800)]
        ) {
            $0.setPointer(at: 0x10, to: 0x800)
            $0.setString("Ragdoll_Head", at: 0x18, storage: 0x300)
        }
        #expect(handle.name == "Ragdoll_Head" && handle.variant?.dataOffset == 0x800)
    }

    @Test func extraAnimationClassesReadTheirSamples() throws {
        let frame = try decodeHKXObject(
            HKADefaultAnimatedReferenceFrame.className, HKADefaultAnimatedReferenceFrame.decode
        ) {
            $0.setVector4(SIMD4(0, 0, 1, 0), at: 0x10)
            $0.setVector4(SIMD4(0, 1, 0, 0), at: 0x20)
            $0.setFloat(2, at: 0x30)
            $0.setArray(at: 0x38, count: 2, dataOffset: 0x400)
            $0.setVector4(SIMD4(0, 0, 0, 0), at: 0x400)
            $0.setVector4(SIMD4(0, 100, 0, 0.5), at: 0x410)
        }
        #expect(frame.duration == 2 && frame.up == SIMD4(0, 0, 1, 0))
        #expect(frame.forward == SIMD4(0, 1, 0, 0))
        #expect(frame.samples.last == SIMD4(0, 100, 0, 0.5))

        let clip = try decodeHKXObject(
            HKAInterleavedUncompressedAnimation.className,
            HKAInterleavedUncompressedAnimation.decode
        ) {
            $0.setFloat(1, at: 0x14)
            $0.setInt32(1, at: 0x18)
            $0.setInt32(1, at: 0x1C)
            $0.setArray(at: 0x38, count: 2, dataOffset: 0x400)
            $0.setArray(at: 0x48, count: 1, dataOffset: 0x600)
            $0.setFloat(0.25, at: 0x600)
            for frame in 0 ..< 2 {
                let base = 0x400 + frame * HKQsTransform.stride
                $0.setVector4(SIMD4(Float(frame), 0, 0, 0), at: base)
                $0.setVector4(SIMD4(0, 0, 0, 1), at: base + 16)
                $0.setVector4(SIMD4(1, 1, 1, 0), at: base + 32)
            }
        }
        #expect(clip.frameCount == 2 && clip.transforms.last?.translation == SIMD3(1, 0, 0))
        #expect(clip.floatTrackCount == 1 && clip.floats == [0.25])
        #expect(clip.annotationTracks.isEmpty)

        let track = try decodeHKXObject(
            HKAAnnotationTrackObject.className, HKAAnnotationTrackObject.decode
        ) {
            $0.setString("Bip01 Root", at: 0x00, storage: 0x300)
            $0.setArray(at: 0x08, count: 1, dataOffset: 0x400)
            $0.setFloat(0.5, at: 0x400)
            $0.setString("FootLeft", at: 0x408, storage: 0x500)
        }
        #expect(track.track.name == "Bip01 Root")
        #expect(track.track.annotations == [HKAAnnotation(time: 0.5, text: "FootLeft")])
    }

    @Test func characterHelpersReadMirrorFootIkAndSequence() throws {
        let mirror = try decodeHKXObject(
            HKBMirroredSkeletonInfo.className, HKBMirroredSkeletonInfo.decode
        ) {
            $0.setVector4(SIMD4(1, 0, 0, 0), at: 0x10)
            $0.setArray(at: 0x20, count: 3, dataOffset: 0x400)
            for (index, bone) in [0, 2, 1].enumerated() {
                $0.setInt16(Int16(bone), at: 0x400 + index * 2)
            }
        }
        #expect(mirror.mirrorAxis == SIMD4(1, 0, 0, 0) && mirror.bonePairMap == [0, 2, 1])

        let footIk = try decodeHKXObject(
            HKBFootIkDriverInfo.className,
            HKBFootIkDriverInfo.decode
        ) {
            $0.setArray(at: 0x10, count: 1, dataOffset: 0x400)
            $0.setFloat(8, at: 0x430)
            $0.setFloat(12, at: 0x434)
            $0.setFloat(170, at: 0x440)
            $0.setFloat(5, at: 0x444)
            $0.setFloat(-2, at: 0x28)
            $0.setInt16(10, at: 0x44C)
            $0.setInt16(11, at: 0x44E)
            $0.setInt16(12, at: 0x450)
            $0.setFloat(50, at: 0x20)
            $0.setFloat(60, at: 0x24)
            $0.setBool(true, at: 0x40)
            $0.setBool(true, at: 0x42)
        }
        let leg = try #require(footIk.legs.first)
        #expect([leg.hipIndex, leg.kneeIndex, leg.ankleIndex] == [10, 11, 12] as [Int])
        #expect(leg.footPlantedAnkleHeightMS == 8 && leg.maxKneeAngleDegrees == 170)
        #expect(leg.footRaisedAnkleHeightMS == 12 && leg.minKneeAngleDegrees == 5)
        #expect(footIk.originalGroundHeightMS == -2)
        #expect(footIk.raycastDistanceUp == 50 && footIk.raycastDistanceDown == 60)
        #expect(footIk.lockFeetWhenPlanted && footIk.isQuadrupedNarrow)

        let sequence = try decodeHKXObject(
            BGSGamebryoSequenceGenerator.className, BGSGamebryoSequenceGenerator.decode
        ) {
            $0.setString("Forward", at: 0x48, storage: 0x300)
            $0.setUInt8(3, at: 0x50)
            $0.setFloat(1, at: 0x54)
        }
        #expect(sequence.sequence == "Forward")
        #expect(sequence.blendModeFunction == 3 && sequence.percent == 1)
    }
}
