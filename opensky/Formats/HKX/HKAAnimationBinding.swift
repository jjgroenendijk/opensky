// hkaAnimationBinding decode for bone-indexed transform samples (todo 6.3).
// 64-bit member offsets from HKX2Library (MIT), cross-checked against
// hkxparse (MIT), probe-verified on Skyrim SE male mt_idle.hkx. HavokLib's
// open reader defines empty transformTrackToBoneIndices as identity mapping.
// Full citations + byte map: docs/formats/hka-animation.md.

import Foundation

nonisolated struct HKXPointerTarget: Equatable {
    let sectionIndex: Int
    let dataOffset: Int
}

nonisolated private struct HKAIndexArrayDescriptor {
    let field: Int
    let name: String
    let sectionIndex: Int
}

nonisolated struct HKAAnimationBinding {
    let originalSkeletonName: String?
    let animationTarget: HKXPointerTarget?
    let transformTrackToBoneIndices: [Int]
    let floatTrackToSlotIndices: [Int]
    let blendHint: Int

    static let className = "hkaAnimationBinding"

    static func bindings(in file: HKXFile) throws -> [HKAAnimationBinding] {
        var result: [HKAAnimationBinding] = []
        for object in file.objects where object.className == className {
            guard file.sections.indices.contains(object.sectionIndex) else { continue }
            let section = file.sections[object.sectionIndex]
            try result.append(decode(
                payload: file.sectionData(at: object.sectionIndex),
                base: object.dataOffset,
                sectionIndex: object.sectionIndex,
                localFixups: section.localFixups,
                globalFixups: section.globalFixups
            ))
        }
        return result
    }

    /// Empty transform map is Havok's compact identity representation.
    func boneIndices(transformTrackCount: Int) throws -> [Int] {
        if transformTrackToBoneIndices.isEmpty {
            return Array(0 ..< transformTrackCount)
        }
        guard transformTrackToBoneIndices.count == transformTrackCount else {
            throw HKASplineAnimationError.countMismatch(
                field: "m_transformTrackToBoneIndices",
                expected: transformTrackCount,
                actual: transformTrackToBoneIndices.count
            )
        }
        for (trackIndex, boneIndex) in transformTrackToBoneIndices.enumerated() {
            guard boneIndex >= 0 else {
                throw HKASplineAnimationError.invalidBoneIndex(
                    trackIndex: trackIndex, boneIndex: boneIndex
                )
            }
        }
        return transformTrackToBoneIndices
    }

    private static let nameField = 0x10
    private static let animationField = 0x18
    private static let transformMapField = 0x20
    private static let floatMapField = 0x30
    private static let blendHintField = 0x40

    private static func decode(
        payload: Data,
        base: Int,
        sectionIndex: Int,
        localFixups: [HKXLocalFixup],
        globalFixups: [HKXGlobalFixup]
    ) throws -> HKAAnimationBinding {
        let local = Dictionary(
            localFixups.map { ($0.fromOffset, $0.toOffset) },
            uniquingKeysWith: { first, _ in first }
        )
        let global = Dictionary(
            globalFixups.map {
                ($0.fromOffset, HKXPointerTarget(
                    sectionIndex: $0.sectionIndex, dataOffset: $0.toOffset
                ))
            },
            uniquingKeysWith: { first, _ in first }
        )
        let name = try local[base + nameField].map { try readString(payload, at: $0) }
        let animationTarget = global[base + animationField]
            ?? local[base + animationField].map {
                HKXPointerTarget(sectionIndex: sectionIndex, dataOffset: $0)
            }
        return try HKAAnimationBinding(
            originalSkeletonName: name,
            animationTarget: animationTarget,
            transformTrackToBoneIndices: readIndices(
                payload,
                base: base,
                descriptor: HKAIndexArrayDescriptor(
                    field: transformMapField,
                    name: "m_transformTrackToBoneIndices",
                    sectionIndex: sectionIndex
                ),
                local: local,
                global: global
            ),
            floatTrackToSlotIndices: readIndices(
                payload,
                base: base,
                descriptor: HKAIndexArrayDescriptor(
                    field: floatMapField,
                    name: "m_floatTrackToFloatSlotIndices",
                    sectionIndex: sectionIndex
                ),
                local: local,
                global: global
            ),
            blendHint: Int(readUInt8(payload, at: base + blendHintField))
        )
    }

    private static func readIndices(
        _ payload: Data,
        base: Int,
        descriptor: HKAIndexArrayDescriptor,
        local: [Int: Int],
        global: [Int: HKXPointerTarget]
    ) throws -> [Int] {
        let count = try readInt(payload, at: base + descriptor.field + 8)
        guard count >= 0 else {
            throw HKASplineAnimationError.invalidMetadata(
                field: descriptor.name, value: String(count)
            )
        }
        guard count > 0 else { return [] }
        let globalOffset = global[base + descriptor.field].flatMap { target in
            target.sectionIndex == descriptor.sectionIndex ? target.dataOffset : nil
        }
        let offset = local[base + descriptor.field] ?? globalOffset
        guard let offset else {
            throw HKASplineAnimationError.missingArrayData(
                field: descriptor.name, count: count
            )
        }
        try requireBounds(offset, count * 2, payload.count, field: descriptor.name)
        var reader = BinaryReader(payload, offset: offset)
        return try (0 ..< count).map { _ in
            try Int(Int16(bitPattern: reader.readUInt16()))
        }
    }

    private static func readString(_ data: Data, at offset: Int) throws -> String {
        var reader = BinaryReader(data, offset: offset)
        return try reader.readZString(encoding: .ascii)
    }

    private static func readInt(_ data: Data, at offset: Int) throws -> Int {
        try requireBounds(offset, 4, data.count, field: "binding metadata")
        var reader = BinaryReader(data, offset: offset)
        return try Int(Int32(bitPattern: reader.readUInt32()))
    }

    private static func readUInt8(_ data: Data, at offset: Int) throws -> UInt8 {
        try requireBounds(offset, 1, data.count, field: "binding metadata")
        return data[offset]
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
}
