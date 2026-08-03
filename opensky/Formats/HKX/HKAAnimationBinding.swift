// hkaAnimationBinding decode for bone-indexed transform samples (todo 6.3).
// 64-bit member offsets from HKX2Library (MIT), cross-checked against
// hkxparse (MIT), probe-verified on Skyrim SE male mt_idle.hkx. HavokLib's
// open reader defines empty transformTrackToBoneIndices as identity mapping.
// Full citations + byte map: docs/formats/hka-animation.md.
//
// Pointer, array, and string resolution goes through the shared object-graph
// helpers (`HKXObjectGraph`, `HKXObjectCursor`, todo 14.1) rather than a
// private fixup dictionary; `HKXPointerTarget` lives there too.

import Foundation

nonisolated struct HKAAnimationBinding {
    let originalSkeletonName: String?
    let animationTarget: HKXPointerTarget?
    let transformTrackToBoneIndices: [Int]
    let floatTrackToSlotIndices: [Int]
    let blendHint: Int

    static let className = "hkaAnimationBinding"

    static func bindings(in file: HKXFile) throws -> [HKAAnimationBinding] {
        let graph = try HKXObjectGraph(file: file)
        var result: [HKAAnimationBinding] = []
        for object in graph.objects(ofClass: className) {
            guard var cursor = graph.cursor(at: object) else { continue }
            try result.append(decode(cursor: &cursor))
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

    private static let nameField = HKXField(0x10, "m_originalSkeletonName")
    private static let animationField = HKXField(0x18, "m_animation")
    private static let transformMapField = HKXField(0x20, "m_transformTrackToBoneIndices")
    private static let floatMapField = HKXField(0x30, "m_floatTrackToFloatSlotIndices")
    private static let blendHintField = HKXField(0x40, "m_blendHint")

    private static func decode(cursor: inout HKXObjectCursor) throws -> HKAAnimationBinding {
        let transformMap = try readIndices(at: transformMapField, cursor: &cursor)
        let floatMap = try readIndices(at: floatMapField, cursor: &cursor)
        guard let blendHint = cursor.uint8(at: blendHintField) else {
            throw HKASplineAnimationError.arrayOutOfBounds(
                field: "binding metadata",
                offset: cursor.base + blendHintField.offset,
                needed: 1,
                available: cursor.payload.count
            )
        }
        return HKAAnimationBinding(
            originalSkeletonName: cursor.string(at: nameField),
            animationTarget: cursor.pointer(at: animationField),
            transformTrackToBoneIndices: transformMap,
            floatTrackToSlotIndices: floatMap,
            blendHint: Int(blendHint)
        )
    }

    /// hkArray<hkInt16>. A negative or unreadable count and a non-empty array
    /// with no fixup to its elements are distinct failures with distinct
    /// errors, so the count is resolved before the element data.
    private static func readIndices(
        at field: HKXField,
        cursor: inout HKXObjectCursor
    ) throws -> [Int] {
        guard let count = cursor.arrayCount(at: field) else {
            throw HKASplineAnimationError.invalidMetadata(
                field: field.name, value: "unreadable"
            )
        }
        guard count > 0 else { return [] }
        guard let indices = cursor.int16Array(at: field) else {
            throw HKASplineAnimationError.missingArrayData(field: field.name, count: count)
        }
        return indices
    }
}
