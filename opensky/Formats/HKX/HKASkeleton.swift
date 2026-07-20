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
        var result: [HKASkeleton] = []
        for object in file.objects where object.className == className {
            guard file.sections.indices.contains(object.sectionIndex) else { continue }
            let payload = try file.sectionData(at: object.sectionIndex)
            let fixups = file.sections[object.sectionIndex].localFixups
            try result.append(decode(
                payload: payload,
                base: object.dataOffset,
                localFixups: fixups
            ))
        }
        return result
    }

    // MARK: - Member offsets (section-local, from the object base)

    // hkaSkeleton member layout, 8-byte pointers (docs/formats/hka-skeleton.md).
    // Only members needed for skinning are decoded; m_referenceFloats,
    // m_floatSlots, m_localFrames are read past (skeleton bind pose needs
    // none of them).
    private static let nameField = 0x10 // m_name hkStringPtr
    private static let parentIndicesField = 0x18 // m_parentIndices hkArray<hkInt16>
    private static let bonesField = 0x28 // m_bones hkArray<hkaBone>, inline stride 16
    private static let referencePoseField = 0x38 // m_referencePose hkArray<hkQsTransform>
    private static let boneStride = 16
    private static let qsTransformStride = 48 // float4 translation + quat + float4 scale

    private static func decode(
        payload: Data,
        base: Int,
        localFixups: [HKXLocalFixup]
    ) throws -> HKASkeleton {
        let fixupMap = Dictionary(
            localFixups.map { ($0.fromOffset, $0.toOffset) },
            uniquingKeysWith: { first, _ in first }
        )

        let name = try fixupMap[base + nameField].map {
            try readString(payload, at: $0)
        }
        let parents = try readParentIndices(payload, base: base, fixupMap: fixupMap)
        let bones = try readBones(payload, base: base, fixupMap: fixupMap)
        let poses = try readReferencePose(payload, base: base, fixupMap: fixupMap)

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

    private static func readParentIndices(
        _ payload: Data,
        base: Int,
        fixupMap: [Int: Int]
    ) throws -> [Int] {
        let (count, dataOffset) = try arrayDescriptor(
            payload, base: base, field: parentIndicesField, fixupMap: fixupMap,
            name: "m_parentIndices"
        )
        guard count > 0 else { return [] }
        guard let dataOffset else {
            throw HKASkeletonError.missingArrayData(field: "m_parentIndices", count: count)
        }
        try requireBounds(dataOffset, count * 2, payload.count, field: "m_parentIndices")
        var reader = BinaryReader(payload, offset: dataOffset)
        return try (0 ..< count).map { _ in try Int(Int16(bitPattern: reader.readUInt16())) }
    }

    private static func readBones(
        _ payload: Data,
        base: Int,
        fixupMap: [Int: Int]
    ) throws -> [HKABone] {
        let (count, dataOffset) = try arrayDescriptor(
            payload, base: base, field: bonesField, fixupMap: fixupMap, name: "m_bones"
        )
        guard count > 0 else { return [] }
        guard let dataOffset else {
            throw HKASkeletonError.missingArrayData(field: "m_bones", count: count)
        }
        try requireBounds(dataOffset, count * boneStride, payload.count, field: "m_bones")
        var bones: [HKABone] = []
        bones.reserveCapacity(count)
        for index in 0 ..< count {
            let boneBase = dataOffset + index * boneStride
            // hkaBone.m_name hkStringPtr sits at element offset 0 -> its fixup
            // fromOffset equals the element start.
            guard let nameOffset = fixupMap[boneBase] else {
                throw HKASkeletonError.boneNameMissing(index: index)
            }
            let name = try readString(payload, at: nameOffset)
            var lockReader = BinaryReader(payload, offset: boneBase + 8)
            let lock = try lockReader.readUInt8() != 0
            bones.append(HKABone(name: name, lockTranslation: lock))
        }
        return bones
    }

    private static func readReferencePose(
        _ payload: Data,
        base: Int,
        fixupMap: [Int: Int]
    ) throws -> [HKABonePose] {
        let (count, dataOffset) = try arrayDescriptor(
            payload, base: base, field: referencePoseField, fixupMap: fixupMap,
            name: "m_referencePose"
        )
        guard count > 0 else { return [] }
        guard let dataOffset else {
            throw HKASkeletonError.missingArrayData(field: "m_referencePose", count: count)
        }
        try requireBounds(
            dataOffset,
            count * qsTransformStride,
            payload.count,
            field: "m_referencePose"
        )
        var poses: [HKABonePose] = []
        poses.reserveCapacity(count)
        for index in 0 ..< count {
            var reader = BinaryReader(payload, offset: dataOffset + index * qsTransformStride)
            // hkQsTransform: translation float4, rotation quat, scale float4.
            // The w lane of translation/scale is junk padding -> not validated.
            let tx = try reader.readFloat32(), ty = try reader.readFloat32()
            let tz = try reader.readFloat32()
            reader.skip(4)
            let qx = try reader.readFloat32(), qy = try reader.readFloat32()
            let qz = try reader.readFloat32(), qw = try reader.readFloat32()
            let sx = try reader.readFloat32(), sy = try reader.readFloat32()
            let sz = try reader.readFloat32()
            let used = [tx, ty, tz, qx, qy, qz, qw, sx, sy, sz]
            guard used.allSatisfy(\.isFinite) else {
                throw HKASkeletonError.nonFiniteTransform(boneIndex: index)
            }
            poses.append(HKABonePose(
                translation: SIMD3(tx, ty, tz),
                rotation: simd_quatf(ix: qx, iy: qy, iz: qz, r: qw),
                scale: SIMD3(sx, sy, sz)
            ))
        }
        return poses
    }

    // MARK: - hkArray + string helpers

    /// hkArray = { ptr(8, null on disk), i32 size @+8, u32 capacityAndFlags
    /// @+12 }. Element data located only via the local fixup whose fromOffset
    /// equals the array field's pointer offset; capacityAndFlags bit31 is a
    /// Havok flag, so the size field (not capacity) drives element counts. A
    /// size-0 array carries a null pointer and no fixup — dataOffset stays nil.
    private static func arrayDescriptor(
        _ payload: Data,
        base: Int,
        field: Int,
        fixupMap: [Int: Int],
        name: String
    ) throws -> (count: Int, dataOffset: Int?) {
        var reader = BinaryReader(payload, offset: base + field + 8)
        let size = try Int(Int32(bitPattern: reader.readUInt32()))
        guard size >= 0 else {
            throw HKASkeletonError.arrayOutOfBounds(
                field: name, offset: base + field, needed: size, available: payload.count
            )
        }
        return (size, fixupMap[base + field])
    }

    private static func readString(_ payload: Data, at offset: Int) throws -> String {
        var reader = BinaryReader(payload, offset: offset)
        return try reader.readZString(encoding: .ascii)
    }

    private static func requireBounds(
        _ offset: Int,
        _ length: Int,
        _ available: Int,
        field: String
    ) throws {
        guard offset >= 0, length >= 0, offset + length <= available else {
            throw HKASkeletonError.arrayOutOfBounds(
                field: field, offset: offset, needed: length, available: available
            )
        }
    }
}
