// hkaSkeleton decode + name-map tests (todo 6.2) over synthetic in-code
// packfiles — never extracted game files (AGENTS.md "Legal & IP boundary").
// Bone names are invented, not vanilla Skyrim bone names. Object byte map:
// docs/formats/hka-skeleton.md.

import Foundation
@testable import opensky
import simd
import Testing

/// Hand-builds one packfile carrying a single hkaSkeleton object at data
/// offset 0, wrapping the payload in a valid container via HKXFixture. Each
/// knob corrupts one axis so a parser guard gets an isolated fixture.
private struct HKASkeletonFixture {
    struct Bone {
        var name: String
        var lock: Bool
    }

    struct Pose {
        var translation: SIMD3<Float>
        var rotation: SIMD4<Float> // x, y, z, w
        var scale: SIMD3<Float>
    }

    /// hkaSkeleton object header size (8-byte pointers, m_localFrames last).
    private static let objectSize = 112

    var skeletonName: String? = "TestRig"
    var bones: [Bone] = [
        Bone(name: "TestRoot", lock: false),
        Bone(name: "TestSpine", lock: true),
        Bone(name: "TestArmL", lock: false),
        Bone(name: "TestArmR", lock: false)
    ]
    var parents: [Int16] = [-1, 0, 1, 0]
    var poses: [Pose] = [
        Pose(translation: SIMD3(0, 0, 0), rotation: SIMD4(0, 0, 0, 1), scale: SIMD3(1, 1, 1)),
        Pose(translation: SIMD3(0, 10, 0), rotation: SIMD4(0, 0, 0, 1), scale: SIMD3(1, 1, 1)),
        Pose(
            translation: SIMD3(5, 0, 0),
            rotation: SIMD4(0, 0, 0.7071, 0.7071),
            scale: SIMD3(2, 2, 2)
        ),
        Pose(translation: SIMD3(-5, 0, 0), rotation: SIMD4(0, 0, 0, 1), scale: SIMD3(1, 1, 1))
    ]

    /// --- Corruption knobs (each isolated to one guard). ---
    /// Writes a bigger m_parentIndices size than bones -> countMismatch.
    var parentSizeOverride: Int?
    /// Writes an oversize m_referencePose size -> arrayOutOfBounds (truncated).
    var poseSizeOverride: Int?
    /// Drops one hkaBone's name fixup -> boneNameMissing.
    var omitBoneNameFixupAt: Int?
    /// Poisons one reference-pose translation.x with NaN -> nonFiniteTransform.
    var nonFiniteBoneAt: Int?

    /// Data region laid out after the object header, with the section-local
    /// offset of every array + string the object's fixups target.
    private struct DataRegion {
        var bytes: Data
        var parentDataOffset: Int
        var bonesDataOffset: Int
        var poseDataOffset: Int
        var skeletonNameOffset: Int?
        var boneNameOffsets: [Int]
    }

    func build() -> Data {
        let region = dataRegion()
        var payload = objectHeader()
        payload.append(region.bytes)

        var fixture = HKXFixture()
        fixture.classNames = [(0x1234_ABCD, "hkaSkeleton")]
        fixture.rootClassIndex = 0
        fixture.rootObjectDataOffset = nil
        fixture.globalFixups = []
        fixture.payloadOverride = payload
        fixture.dataPayloadSize = payload.count
        fixture.localFixups = localFixups(region)
        fixture.virtualFixups = [.init(
            dataOffset: 0,
            classNameSection: 0,
            classNameOffset: UInt32(fixture.nameOffset(ofClass: 0))
        )]
        return fixture.build()
    }

    /// 112-byte object header: only the three hkArray size fields carry data
    /// (pointers null on disk, patched by fixups).
    private func objectHeader() -> Data {
        var obj = [UInt8](repeating: 0, count: Self.objectSize)
        func writeU32(_ value: UInt32, at offset: Int) {
            obj[offset] = UInt8(value & 0xFF)
            obj[offset + 1] = UInt8((value >> 8) & 0xFF)
            obj[offset + 2] = UInt8((value >> 16) & 0xFF)
            obj[offset + 3] = UInt8((value >> 24) & 0xFF)
        }
        // m_parentIndices size @0x20, m_bones size @0x30, m_referencePose @0x40.
        writeU32(UInt32(parentSizeOverride ?? parents.count), at: 0x20)
        writeU32(UInt32(bones.count), at: 0x30)
        writeU32(UInt32(poseSizeOverride ?? poses.count), at: 0x40)
        return Data(obj)
    }

    private func dataRegion() -> DataRegion {
        var region = Data()
        let base = Self.objectSize
        let parentDataOffset = base + region.count
        for parent in parents {
            region.appendUInt16(UInt16(bitPattern: parent))
        }
        let bonesDataOffset = base + region.count
        for bone in bones {
            region.append(Data(repeating: 0, count: 8)) // m_name hkStringPtr (null on disk)
            region.append(bone.lock ? 1 : 0)
            region.append(Data(repeating: 0, count: 7)) // pad to stride 16
        }
        let poseDataOffset = base + region.count
        appendPoses(to: &region)

        var skeletonNameOffset: Int?
        if let skeletonName {
            skeletonNameOffset = base + region.count
            region.append(Data(skeletonName.utf8))
            region.append(0)
        }
        var boneNameOffsets: [Int] = []
        for bone in bones {
            boneNameOffsets.append(base + region.count)
            region.append(Data(bone.name.utf8))
            region.append(0)
        }
        return DataRegion(
            bytes: region,
            parentDataOffset: parentDataOffset,
            bonesDataOffset: bonesDataOffset,
            poseDataOffset: poseDataOffset,
            skeletonNameOffset: skeletonNameOffset,
            boneNameOffsets: boneNameOffsets
        )
    }

    private func appendPoses(to region: inout Data) {
        for (index, pose) in poses.enumerated() {
            let translationX = nonFiniteBoneAt == index ? Float.nan : pose.translation.x
            region.appendFloat32(translationX)
            region.appendFloat32(pose.translation.y)
            region.appendFloat32(pose.translation.z)
            region.appendFloat32(.nan) // translation w padding — parser must ignore
            region.appendFloat32(pose.rotation.x)
            region.appendFloat32(pose.rotation.y)
            region.appendFloat32(pose.rotation.z)
            region.appendFloat32(pose.rotation.w)
            region.appendFloat32(pose.scale.x)
            region.appendFloat32(pose.scale.y)
            region.appendFloat32(pose.scale.z)
            region.appendFloat32(.nan) // scale w padding — parser must ignore
        }
    }

    /// Local fixups patch each null pointer to its data target.
    private func localFixups(_ region: DataRegion) -> [HKXFixture.LocalFixup] {
        var fixups: [HKXFixture.LocalFixup] = []
        if let offset = region.skeletonNameOffset {
            fixups.append(.init(from: 0x10, toOffset: UInt32(offset)))
        }
        if !parents.isEmpty {
            fixups.append(.init(from: 0x18, toOffset: UInt32(region.parentDataOffset)))
        }
        if !bones.isEmpty {
            fixups.append(.init(from: 0x28, toOffset: UInt32(region.bonesDataOffset)))
        }
        if !poses.isEmpty {
            fixups.append(.init(from: 0x38, toOffset: UInt32(region.poseDataOffset)))
        }
        for (index, offset) in region.boneNameOffsets.enumerated() {
            guard omitBoneNameFixupAt != index else { continue }
            fixups.append(.init(
                from: UInt32(region.bonesDataOffset + index * 16),
                toOffset: UInt32(offset)
            ))
        }
        return fixups
    }
}

struct HKASkeletonTests {
    private func firstSkeleton(_ fixture: HKASkeletonFixture) throws -> HKASkeleton {
        let file = try HKXFile(data: fixture.build())
        let skeletons = try HKASkeleton.skeletons(in: file)
        return try #require(skeletons.first)
    }

    private func skeletonError(_ fixture: HKASkeletonFixture) -> HKASkeletonError? {
        do {
            _ = try HKASkeleton.skeletons(in: HKXFile(data: fixture.build()))
            return nil
        } catch let error as HKASkeletonError {
            return error
        } catch {
            return nil
        }
    }

    // MARK: - Happy path

    @Test func decodesNamesParentsAndPose() throws {
        let skeleton = try firstSkeleton(HKASkeletonFixture())
        #expect(skeleton.name == "TestRig")
        #expect(skeleton.boneNames == ["TestRoot", "TestSpine", "TestArmL", "TestArmR"])
        #expect(skeleton.lockTranslation == [false, true, false, false])
        #expect(skeleton.parentIndices == [-1, 0, 1, 0])
        #expect(skeleton.boneCount == 4)
        #expect(skeleton.rootIndices == [0])

        let arm = skeleton.referencePose[2]
        #expect(arm.translation == SIMD3<Float>(5, 0, 0))
        #expect(arm.rotation.vector == SIMD4<Float>(0, 0, 0.7071, 0.7071))
        #expect(arm.scale == SIMD3<Float>(2, 2, 2))
    }

    @Test func ignoresQsTransformPaddingLanes() throws {
        // Translation/scale w lanes are written NaN in the fixture; a clean
        // decode proves they never reach engine math.
        let skeleton = try firstSkeleton(HKASkeletonFixture())
        for pose in skeleton.referencePose {
            #expect(pose.translation.x.isFinite)
            #expect(pose.scale.z.isFinite)
        }
    }

    @Test func decodesEmptySkeleton() throws {
        // Size-0 arrays carry a null pointer and no fixup — must not error.
        var fixture = HKASkeletonFixture()
        fixture.bones = []
        fixture.parents = []
        fixture.poses = []
        fixture.skeletonName = "EmptyRig"
        let skeleton = try firstSkeleton(fixture)
        #expect(skeleton.name == "EmptyRig")
        #expect(skeleton.boneNames.isEmpty)
        #expect(skeleton.parentIndices.isEmpty)
        #expect(skeleton.referencePose.isEmpty)
        #expect(skeleton.rootIndices.isEmpty)
    }

    @Test func decodesMultipleRoots() throws {
        // Vanilla human rig carries two parent==-1 bones; no single-root assumption.
        var fixture = HKASkeletonFixture()
        fixture.parents = [-1, 0, -1, 2]
        let skeleton = try firstSkeleton(fixture)
        #expect(skeleton.rootIndices == [0, 2])
    }

    @Test func decodesNullSkeletonName() throws {
        var fixture = HKASkeletonFixture()
        fixture.skeletonName = nil // hkStringPtr with no fixup -> nil, not a trap
        let skeleton = try firstSkeleton(fixture)
        #expect(skeleton.name == nil)
        #expect(skeleton.boneNames.count == 4)
    }

    // MARK: - Malformed input (one axis each)

    @Test func rejectsCountMismatch() {
        var fixture = HKASkeletonFixture()
        fixture.parentSizeOverride = 5 // 5 parents vs 4 bones/poses
        #expect(skeletonError(fixture) == .countMismatch(bones: 4, parents: 5, poses: 4))
    }

    @Test func rejectsParentOutOfRange() {
        var fixture = HKASkeletonFixture()
        fixture.parents = [-1, 0, 99, 1] // 99 >= boneCount
        #expect(skeletonError(fixture) == .parentOutOfRange(index: 2, parent: 99, boneCount: 4))
    }

    @Test func rejectsMissingBoneNameFixup() {
        var fixture = HKASkeletonFixture()
        fixture.omitBoneNameFixupAt = 1
        #expect(skeletonError(fixture) == .boneNameMissing(index: 1))
    }

    @Test func rejectsTruncatedPoseArray() throws {
        var fixture = HKASkeletonFixture()
        fixture.poseSizeOverride = 500 // 500 * 48 bytes runs past the payload
        let error = try #require(skeletonError(fixture))
        guard case .arrayOutOfBounds(field: "m_referencePose", _, _, _) = error else {
            Issue.record("expected arrayOutOfBounds on m_referencePose, got \(error)")
            return
        }
    }

    @Test func rejectsNonFiniteTransform() {
        var fixture = HKASkeletonFixture()
        fixture.nonFiniteBoneAt = 2
        #expect(skeletonError(fixture) == .nonFiniteTransform(boneIndex: 2))
    }
}

struct SkeletonBoneMapTests {
    @Test func fullMatch() {
        let map = SkeletonBoneMap(
            hkxBoneNames: ["Root", "Spine", "Head"],
            nifNodeNames: ["Root", "Spine", "Head"]
        )
        #expect(map.matchedCount == 3)
        #expect(map.matched == ["Root", "Spine", "Head"])
        #expect(map.unmatchedHKX.isEmpty)
        #expect(map.unmatchedNIF.isEmpty)
    }

    @Test func partialMatchTagsBothDirections() {
        let map = SkeletonBoneMap(
            hkxBoneNames: ["Root", "Spine", "WeaponAttach"],
            nifNodeNames: ["Root", "Spine", "MeshOnlyNode"]
        )
        #expect(map.matchedCount == 2)
        #expect(map.matched == ["Root", "Spine"])

        let hkxOnly = try? #require(map.unmatchedHKX.first)
        #expect(hkxOnly?.name == "WeaponAttach")
        #expect(hkxOnly?.reason.isEmpty == false)

        let nifOnly = try? #require(map.unmatchedNIF.first)
        #expect(nifOnly?.name == "MeshOnlyNode")
        #expect(nifOnly?.reason.isEmpty == false)
    }

    @Test func everyMismatchCarriesReason() {
        let map = SkeletonBoneMap(
            hkxBoneNames: ["A", "B"],
            nifNodeNames: ["C", "D"]
        )
        #expect(map.matchedCount == 0)
        #expect(map.unmatchedHKX.allSatisfy { !$0.reason.isEmpty })
        #expect(map.unmatchedNIF.allSatisfy { !$0.reason.isEmpty })
        #expect(map.unmatchedNIF.map(\.name) == ["C", "D"]) // sorted, deterministic
    }
}
