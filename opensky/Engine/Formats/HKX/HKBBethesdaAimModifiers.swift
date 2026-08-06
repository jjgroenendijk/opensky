// Bethesda's own modifier classes (todo 14.2), part two: the two aiming
// modifiers. `BSDirectAtModifier` swings a bone chain towards a target or the
// camera — the spine bend that makes the player face where they aim — and
// `BSLookAtModifier` does the same for head and eye bones with per-bone gains.
// They are split into their own file because between them they declare fifty
// members, which would put the part-one file past the lint cap.
//
// 64-bit member offsets from ret2end/HKX2Library (MIT); signatures match the
// local SSE files (BSDirectAtModifier 0x19A005C0, BSLookAtModifier 0xD756FC25,
// BSLookAtModifierBoneData 0x29EFEE59). No Havok SDK, Creation Kit, or SKSE
// internals consulted (AGENTS.md Legal & IP). Byte map:
// docs/formats/hkx-behavior-nodes.md.

import Foundation

/// Decoded `BSDirectAtModifier`, size 224.
nonisolated struct BSDirectAtModifier: HKBClass, Equatable {
    let modifier: HKBModifierHeader
    let directAtTarget: Bool
    /// The bone whose forward axis is aimed.
    let sourceBoneIndex: Int
    /// First and last bone of the chain the rotation is spread across.
    let startBoneIndex: Int
    let endBoneIndex: Int
    let limitHeadingDegrees: Float
    let limitPitchDegrees: Float
    let offsetHeadingDegrees: Float
    let offsetPitchDegrees: Float
    /// Response rates when the modifier engages and when it releases.
    let onGain: Float
    let offGain: Float
    let targetLocation: SIMD4<Float>
    let userInfo: UInt32
    let directAtCamera: Bool
    let directAtCameraX: Float
    let directAtCameraY: Float
    let directAtCameraZ: Float
    let active: Bool
    let currentHeadingOffset: Float
    let currentPitchOffset: Float
    let unresolved: [HKXUnresolvedReference]

    static let className = "BSDirectAtModifier"

    private static let directAtTargetField = HKXField(0x50, "m_directAtTarget")
    private static let sourceBoneField = HKXField(0x52, "m_sourceBoneIndex")
    private static let startBoneField = HKXField(0x54, "m_startBoneIndex")
    private static let endBoneField = HKXField(0x56, "m_endBoneIndex")
    private static let limitHeadingField = HKXField(0x58, "m_limitHeadingDegrees")
    private static let limitPitchField = HKXField(0x5C, "m_limitPitchDegrees")
    private static let offsetHeadingField = HKXField(0x60, "m_offsetHeadingDegrees")
    private static let offsetPitchField = HKXField(0x64, "m_offsetPitchDegrees")
    private static let onGainField = HKXField(0x68, "m_onGain")
    private static let offGainField = HKXField(0x6C, "m_offGain")
    private static let targetLocationField = HKXField(0x70, "m_targetLocation")
    private static let userInfoField = HKXField(0x80, "m_userInfo")
    private static let directAtCameraField = HKXField(0x84, "m_directAtCamera")
    private static let cameraXField = HKXField(0x88, "m_directAtCameraX")
    private static let cameraYField = HKXField(0x8C, "m_directAtCameraY")
    private static let cameraZField = HKXField(0x90, "m_directAtCameraZ")
    private static let activeField = HKXField(0x94, "m_active")
    private static let currentHeadingField = HKXField(0x98, "m_currentHeadingOffset")
    private static let currentPitchField = HKXField(0x9C, "m_currentPitchOffset")

    static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> BSDirectAtModifier?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        let header = HKBModifierHeader.decode(&cursor)
        return BSDirectAtModifier(
            modifier: header,
            directAtTarget: cursor.bool(at: directAtTargetField) ?? false,
            sourceBoneIndex: cursor.int16(at: sourceBoneField) ?? -1,
            startBoneIndex: cursor.int16(at: startBoneField) ?? -1,
            endBoneIndex: cursor.int16(at: endBoneField) ?? -1,
            limitHeadingDegrees: cursor.float32(at: limitHeadingField) ?? 0,
            limitPitchDegrees: cursor.float32(at: limitPitchField) ?? 0,
            offsetHeadingDegrees: cursor.float32(at: offsetHeadingField) ?? 0,
            offsetPitchDegrees: cursor.float32(at: offsetPitchField) ?? 0,
            onGain: cursor.float32(at: onGainField) ?? 0,
            offGain: cursor.float32(at: offGainField) ?? 0,
            targetLocation: cursor.vector4(at: targetLocationField) ?? SIMD4(),
            userInfo: cursor.uint32(at: userInfoField) ?? 0,
            directAtCamera: cursor.bool(at: directAtCameraField) ?? false,
            directAtCameraX: cursor.float32(at: cameraXField) ?? 0,
            directAtCameraY: cursor.float32(at: cameraYField) ?? 0,
            directAtCameraZ: cursor.float32(at: cameraZField) ?? 0,
            active: cursor.bool(at: activeField) ?? false,
            currentHeadingOffset: cursor.float32(at: currentHeadingField) ?? 0,
            currentPitchOffset: cursor.float32(at: currentPitchField) ?? 0,
            unresolved: cursor.unresolved
        )
    }

    var nodeName: String? {
        modifier.name
    }

    var references: [HKBReference] {
        modifier.references
    }

    var summary: String {
        "bones \(startBoneIndex)-\(endBoneIndex), limits "
            + "\(limitHeadingDegrees)/\(limitPitchDegrees) deg, camera \(directAtCamera)"
    }
}

/// One entry of `BSLookAtModifier::m_bones` or `m_eyeBones`, 64 bytes.
nonisolated struct BSLookAtBoneData: Equatable {
    let index: Int
    /// The bone's forward axis in its own local space.
    let forwardAxisLS: SIMD4<Float>
    let limitAngleDegrees: Float
    let onGain: Float
    let offGain: Float
    let enabled: Bool

    static let stride = 64

    static func decode(
        _ element: inout HKXObjectCursor,
        member: String,
        index: Int
    ) -> BSLookAtBoneData {
        let label = "\(member)[\(index)]"
        return BSLookAtBoneData(
            index: element.int16(at: HKXField(0x00, "\(label).m_index")) ?? -1,
            forwardAxisLS: element
                .vector4(at: HKXField(0x10, "\(label).m_fwdAxisLS")) ?? SIMD4(),
            limitAngleDegrees: element
                .float32(at: HKXField(0x20, "\(label).m_limitAngleDegrees")) ?? 0,
            onGain: element.float32(at: HKXField(0x24, "\(label).m_onGain")) ?? 0,
            offGain: element.float32(at: HKXField(0x28, "\(label).m_offGain")) ?? 0,
            enabled: element.bool(at: HKXField(0x2C, "\(label).m_enabled")) ?? false
        )
    }
}

/// Decoded `BSLookAtModifier`, size 224.
nonisolated struct BSLookAtModifier: HKBClass, Equatable {
    let modifier: HKBModifierHeader
    let lookAtTarget: Bool
    let bones: [BSLookAtBoneData]
    let eyeBones: [BSLookAtBoneData]
    let limitAngleDegrees: Float
    let limitAngleThresholdDegrees: Float
    let continueLookOutsideOfLimit: Bool
    let onGain: Float
    let offGain: Float
    /// When true each bone's own gains override the modifier-wide ones.
    let useBoneGains: Bool
    let targetLocation: SIMD4<Float>
    let targetOutsideLimits: Bool
    /// Raised when the target leaves the permitted cone.
    let targetOutOfLimitEvent: HKBEventProperty
    let lookAtCamera: Bool
    let lookAtCameraX: Float
    let lookAtCameraY: Float
    let lookAtCameraZ: Float
    let unresolved: [HKXUnresolvedReference]

    static let className = "BSLookAtModifier"

    private static let lookAtTargetField = HKXField(0x50, "m_lookAtTarget")
    private static let bonesField = HKXField(0x58, "m_bones")
    private static let eyeBonesField = HKXField(0x68, "m_eyeBones")
    private static let limitAngleField = HKXField(0x78, "m_limitAngleDegrees")
    private static let limitThresholdField = HKXField(
        0x7C, "m_limitAngleThresholdDegrees"
    )
    private static let continueOutsideField = HKXField(
        0x80, "m_continueLookOutsideOfLimit"
    )
    private static let onGainField = HKXField(0x84, "m_onGain")
    private static let offGainField = HKXField(0x88, "m_offGain")
    private static let useBoneGainsField = HKXField(0x8C, "m_useBoneGains")
    private static let targetLocationField = HKXField(0x90, "m_targetLocation")
    private static let outsideLimitsField = HKXField(0xA0, "m_targetOutsideLimits")
    private static let outOfLimitEventOffset = 0xA8
    private static let lookAtCameraField = HKXField(0xB8, "m_lookAtCamera")
    private static let cameraXField = HKXField(0xBC, "m_lookAtCameraX")
    private static let cameraYField = HKXField(0xC0, "m_lookAtCameraY")
    private static let cameraZField = HKXField(0xC4, "m_lookAtCameraZ")

    static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> BSLookAtModifier?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        let header = HKBModifierHeader.decode(&cursor)
        let bones = boneData(at: bonesField, member: "m_bones", &cursor, graph)
        let eyeBones = boneData(at: eyeBonesField, member: "m_eyeBones", &cursor, graph)
        let outOfLimit = HKBEventProperty.decode(
            &cursor, at: outOfLimitEventOffset, named: "m_targetOutOfLimitEvent"
        )
        return BSLookAtModifier(
            modifier: header,
            lookAtTarget: cursor.bool(at: lookAtTargetField) ?? false,
            bones: bones,
            eyeBones: eyeBones,
            limitAngleDegrees: cursor.float32(at: limitAngleField) ?? 0,
            limitAngleThresholdDegrees: cursor.float32(at: limitThresholdField) ?? 0,
            continueLookOutsideOfLimit: cursor.bool(at: continueOutsideField) ?? false,
            onGain: cursor.float32(at: onGainField) ?? 0,
            offGain: cursor.float32(at: offGainField) ?? 0,
            useBoneGains: cursor.bool(at: useBoneGainsField) ?? false,
            targetLocation: cursor.vector4(at: targetLocationField) ?? SIMD4(),
            targetOutsideLimits: cursor.bool(at: outsideLimitsField) ?? false,
            targetOutOfLimitEvent: outOfLimit,
            lookAtCamera: cursor.bool(at: lookAtCameraField) ?? false,
            lookAtCameraX: cursor.float32(at: cameraXField) ?? 0,
            lookAtCameraY: cursor.float32(at: cameraYField) ?? 0,
            lookAtCameraZ: cursor.float32(at: cameraZField) ?? 0,
            unresolved: cursor.unresolved
        )
    }

    private static func boneData(
        at field: HKXField,
        member: String,
        _ cursor: inout HKXObjectCursor,
        _ graph: HKXObjectGraph
    ) -> [BSLookAtBoneData] {
        guard let view = cursor.array(at: field) else { return [] }
        var entries: [BSLookAtBoneData] = []
        entries.reserveCapacity(view.count)
        for index in 0 ..< view.count {
            guard
                var element = graph.element(
                    of: view, index: index, stride: BSLookAtBoneData.stride
                )
            else {
                cursor.recordMiss(field, .outOfBounds)
                continue
            }
            entries.append(BSLookAtBoneData.decode(&element, member: member, index: index))
            cursor.absorb(element)
        }
        return entries
    }

    var nodeName: String? {
        modifier.name
    }

    var references: [HKBReference] {
        modifier.references
            + targetOutOfLimitEvent.references(named: "m_targetOutOfLimitEvent")
    }

    var summary: String {
        "\(bones.count) bones, \(eyeBones.count) eye bones, "
            + "limit \(limitAngleDegrees) deg"
    }
}
