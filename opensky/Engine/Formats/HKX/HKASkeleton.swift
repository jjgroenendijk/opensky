// hkaSkeleton object decode (todo 6.2): bone names, parent indices, reference
// pose. Locates each hkaSkeleton in the packfile via the container's virtual-
// fixup inventory (6.1), then reads the object's inline members out of the
// __data__ section payload, resolving hkArray + hkStringPtr pointers through
// the section's local fixups (pointers are null on disk — the "finish" pass
// patches them at load, we read the fixup targets instead).
//
// No public Havok spec. Object layout reimplemented from independent open
// parsers — exyorha/hkxparse (MIT), ret2end/HKX2Library (MIT) — plus the
// ZeldaMods wiki "Havok" hkaSkeleton table, then probe-verified byte-by-byte
// against the local SSE skeleton.hkx (human + wolf rigs, both rig + ragdoll
// skeletons; all hk_2010.2.0-r1 64-bit LE). No Havok SDK or Bethesda code
// consulted (AGENTS.md Legal & IP). Byte map + citations:
// docs/formats/hka-skeleton.md.

import Foundation
import simd

nonisolated enum HKASkeletonError: Error, Equatable {
    /// hkArray/hkStringPtr target runs past the section payload.
    case arrayOutOfBounds(field: String, offset: Int, needed: Int, available: Int)
    /// hkArray reports elements but carries no local fixup to their data.
    case missingArrayData(field: String, count: Int)
    /// hkaBone element has no name-string fixup (name is load-bearing).
    case boneNameMissing(index: Int)
    /// m_parentIndices, m_bones, m_referencePose element counts disagree.
    case countMismatch(bones: Int, parents: Int, poses: Int)
    /// Parent index is neither -1 (root) nor a valid bone index.
    case parentOutOfRange(index: Int, parent: Int, boneCount: Int)
    /// A reference-pose lane the engine uses is NaN/inf (w padding excluded).
    case nonFiniteTransform(boneIndex: Int)
}

/// One bone's bind transform in its parent's space. Havok hkQsTransform packs
/// translation/scale as float4 with a junk w lane — decoded to SIMD3 so the
/// padding never leaks into engine math.
nonisolated struct HKABonePose: Equatable {
    let translation: SIMD3<Float>
    let rotation: simd_quatf
    let scale: SIMD3<Float>

    static func == (lhs: HKABonePose, rhs: HKABonePose) -> Bool {
        lhs.translation == rhs.translation
            && lhs.rotation.vector == rhs.rotation.vector
            && lhs.scale == rhs.scale
    }
}

/// One skeleton bone: name (skin/NIF-node key) + whether its translation is
/// locked by the ragdoll (`m_lockTranslation`).
nonisolated struct HKABone: Equatable {
    let name: String
    let lockTranslation: Bool
}

/// Decoded hkaSkeleton: the bone hierarchy + bind pose one HKX packfile holds.
/// `parentIndices[i]` is bone i's parent (-1 for a root — vanilla human rigs
/// carry two roots, so callers must not assume one). Reference pose is
/// parent-relative, matching NIF NiNode local transforms.
nonisolated struct HKASkeleton {
    let name: String?
    let bones: [HKABone]
    let parentIndices: [Int]
    let referencePose: [HKABonePose]

    var boneNames: [String] {
        bones.map(\.name)
    }

    var lockTranslation: [Bool] {
        bones.map(\.lockTranslation)
    }

    var boneCount: Int {
        bones.count
    }

    /// Bone indices with no parent. Multiple in vanilla rigs (extra control
    /// node beside the skeleton root).
    var rootIndices: [Int] {
        parentIndices.enumerated().filter { $0.element == -1 }.map(\.offset)
    }

    static let className = "hkaSkeleton"

    /// Every hkaSkeleton in the packfile, in inventory order (rig before
    /// ragdoll in vanilla skeleton.hkx). Objects located via the container's
    /// virtual fixups; a malformed one throws rather than corrupting the set.
    static func skeletons(in file: HKXFile) throws -> [HKASkeleton] {
        let graph = try HKXObjectGraph(file: file)
        var result: [HKASkeleton] = []
        for object in graph.objects(ofClass: className) {
            guard var cursor = graph.cursor(at: object) else { continue }
            try result.append(decode(cursor: &cursor))
        }
        return result
    }

    // MARK: - Member offsets (section-local, from the object base)

    // hkaSkeleton member layout, 8-byte pointers (docs/formats/hka-skeleton.md).
    // Only members needed for skinning are decoded; m_referenceFloats,
    // m_floatSlots, m_localFrames are read past (skeleton bind pose needs
    // none of them).
    private static let nameField = HKXField(0x10, "m_name") // hkStringPtr
    private static let parentIndicesField = HKXField(0x18, "m_parentIndices")
    private static let bonesField = HKXField(0x28, "m_bones") // inline stride 16
    private static let referencePoseField = HKXField(0x38, "m_referencePose")
    private static let boneStride = 16
    private static let qsTransformStride = 48 // float4 translation + quat + float4 scale
    private static let boneNameField = HKXField(0x00, "hkaBone::m_name")
    private static let boneLockField = HKXField(0x08, "hkaBone::m_lockTranslation")

    private static func decode(cursor: inout HKXObjectCursor) throws -> HKASkeleton {
        let name = cursor.string(at: nameField)
        let parents = try readParentIndices(cursor: &cursor)
        let bones = try readBones(cursor: &cursor)
        let poses = try readReferencePose(cursor: &cursor)

        guard parents.count == bones.count, poses.count == bones.count else {
            throw HKASkeletonError.countMismatch(
                bones: bones.count,
                parents: parents.count,
                poses: poses.count
            )
        }
        for (index, parent) in parents.enumerated() where parent != -1 {
            guard parent >= 0, parent < bones.count else {
                throw HKASkeletonError.parentOutOfRange(
                    index: index,
                    parent: parent,
                    boneCount: bones.count
                )
            }
        }
        return HKASkeleton(
            name: name,
            bones: bones,
            parentIndices: parents,
            referencePose: poses
        )
    }

    // MARK: - Members

    private static func readParentIndices(cursor: inout HKXObjectCursor) throws -> [Int] {
        let count = try count(at: parentIndicesField, cursor: &cursor)
        guard count > 0 else { return [] }
        guard let parents = cursor.int16Array(at: parentIndicesField) else {
            throw HKASkeletonError.missingArrayData(field: parentIndicesField.name, count: count)
        }
        return parents
    }

    private static func readBones(cursor: inout HKXObjectCursor) throws -> [HKABone] {
        let count = try count(at: bonesField, cursor: &cursor)
        guard count > 0 else { return [] }
        guard let view = cursor.array(at: bonesField) else {
            throw HKASkeletonError.missingArrayData(field: bonesField.name, count: count)
        }
        var bones: [HKABone] = []
        bones.reserveCapacity(count)
        for index in 0 ..< count {
            guard
                var element = cursor.graph.element(
                    of: view, index: index, stride: boneStride
                )
            else {
                throw HKASkeletonError.arrayOutOfBounds(
                    field: bonesField.name,
                    offset: view.dataOffset,
                    needed: count * boneStride,
                    available: cursor.payload.count
                )
            }
            // hkaBone.m_name hkStringPtr sits at element offset 0, and a bone
            // without a name is not usable for skinning.
            guard let name = element.string(at: boneNameField) else {
                throw HKASkeletonError.boneNameMissing(index: index)
            }
            bones.append(HKABone(
                name: name,
                lockTranslation: (element.uint8(at: boneLockField) ?? 0) != 0
            ))
            cursor.absorb(element)
        }
        return bones
    }

    private static func readReferencePose(
        cursor: inout HKXObjectCursor
    ) throws -> [HKABonePose] {
        let count = try count(at: referencePoseField, cursor: &cursor)
        guard count > 0 else { return [] }
        guard let view = cursor.array(at: referencePoseField) else {
            throw HKASkeletonError.missingArrayData(field: referencePoseField.name, count: count)
        }
        var poses: [HKABonePose] = []
        poses.reserveCapacity(count)
        for index in 0 ..< count {
            guard
                var element = cursor.graph.element(
                    of: view, index: index, stride: qsTransformStride
                ),
                let pose = pose(from: &element)
            else {
                throw HKASkeletonError.arrayOutOfBounds(
                    field: referencePoseField.name,
                    offset: view.dataOffset,
                    needed: count * qsTransformStride,
                    available: cursor.payload.count
                )
            }
            guard pose.isFinite else {
                throw HKASkeletonError.nonFiniteTransform(boneIndex: index)
            }
            poses.append(pose.value)
            cursor.absorb(element)
        }
        return poses
    }

    /// hkQsTransform: translation float4, rotation quat, scale float4. The w
    /// lane of translation and scale is junk padding, so it is neither read
    /// into the pose nor validated.
    private static func pose(
        from element: inout HKXObjectCursor
    ) -> (value: HKABonePose, isFinite: Bool)? {
        var lanes: [Float] = []
        for offset in stride(from: 0, to: qsTransformStride, by: 4) {
            guard let lane = element.float32(at: HKXField(offset, "hkQsTransform")) else {
                return nil
            }
            lanes.append(lane)
        }
        let used = [
            lanes[0], lanes[1], lanes[2],
            lanes[4], lanes[5], lanes[6], lanes[7],
            lanes[8], lanes[9], lanes[10]
        ]
        let pose = HKABonePose(
            translation: SIMD3(lanes[0], lanes[1], lanes[2]),
            rotation: simd_quatf(ix: lanes[4], iy: lanes[5], iz: lanes[6], r: lanes[7]),
            scale: SIMD3(lanes[8], lanes[9], lanes[10])
        )
        return (pose, used.allSatisfy(\.isFinite))
    }

    /// hkArray = { ptr(8, null on disk), i32 size @+8, u32 capacityAndFlags
    /// @+12 }; capacityAndFlags bit 31 is a Havok flag, so the size field (not
    /// capacity) drives element counts. A negative or unreadable size is a
    /// malformed descriptor, distinct from a well-formed empty array.
    private static func count(
        at field: HKXField,
        cursor: inout HKXObjectCursor
    ) throws -> Int {
        guard let size = cursor.arrayCount(at: field) else {
            throw HKASkeletonError.arrayOutOfBounds(
                field: field.name,
                offset: cursor.base + field.offset,
                needed: 4,
                available: cursor.payload.count
            )
        }
        return size
    }
}
