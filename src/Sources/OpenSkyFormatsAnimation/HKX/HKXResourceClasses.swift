// Havok classes beside the animation and physics data: the resource tree the
// export tool writes, the extracted motion of a clip, the uncompressed clip
// format, and an annotation track stored as its own tagfile object. Offsets
// from HKX2Library (MIT). Byte map: docs/formats/hkx-physics.md.

import Foundation

/// Decoded `hkMemoryResourceContainer`, size 64: a named folder of resource
/// handles. The export tool writes the tree; the game reads the root variants.
nonisolated public struct HKMemoryResourceContainer: HKBClass, Equatable, Sendable {
    public let name: String?
    public let resourceHandles: [HKXPointerTarget?]
    public let children: [HKXPointerTarget?]
    public let unresolved: [HKXUnresolvedReference]

    public static let className = "hkMemoryResourceContainer"

    public static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> HKMemoryResourceContainer?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        return HKMemoryResourceContainer(
            name: cursor.string(at: HKXField(0x10, "m_name")),
            resourceHandles: cursor.pointerArray(at: HKXField(0x20, "m_resourceHandles")),
            children: cursor.pointerArray(at: HKXField(0x30, "m_children")),
            unresolved: cursor.unresolved
        )
    }

    public var references: [HKBReference] {
        HKBReference.each("m_resourceHandles", resourceHandles)
            + HKBReference.each("m_children", children)
    }

    public var summary: String {
        "\(name ?? "<unnamed>"): \(resourceHandles.count) handles, \(children.count) children"
    }
}

/// Decoded `hkMemoryResourceHandle`, size 48: one named object of the tree.
nonisolated public struct HKMemoryResourceHandle: HKBClass, Equatable, Sendable {
    public let name: String?
    public let variant: HKXPointerTarget?
    public let unresolved: [HKXUnresolvedReference]

    public static let className = "hkMemoryResourceHandle"

    public static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> HKMemoryResourceHandle?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        return HKMemoryResourceHandle(
            name: cursor.string(at: HKXField(0x18, "m_name")),
            variant: cursor.optionalPointer(at: HKXField(0x10, "m_variant")),
            unresolved: cursor.unresolved
        )
    }

    public var references: [HKBReference] {
        HKBReference.optional("m_variant", variant)
    }

    public var summary: String {
        name ?? "<unnamed handle>"
    }
}

/// Decoded `hkaDefaultAnimatedReferenceFrame`, size 80: the motion taken out of
/// a clip's root, sampled evenly over its duration. Each sample is a position
/// and, in w, the heading in radians.
nonisolated public struct HKADefaultAnimatedReferenceFrame: HKBClass, Equatable, Sendable {
    public let up: SIMD4<Float>
    public let forward: SIMD4<Float>
    public let duration: Float
    public let samples: [SIMD4<Float>]
    public let unresolved: [HKXUnresolvedReference]

    public static let className = "hkaDefaultAnimatedReferenceFrame"

    public static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> HKADefaultAnimatedReferenceFrame?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        let samples = cursor.structArray(
            at: HKXField(0x38, "m_referenceFrameSamples"), stride: 16
        ) { element, index in
            element.vector4(at: HKXField(0, "m_referenceFrameSamples[\(index)]")) ?? SIMD4()
        }
        return HKADefaultAnimatedReferenceFrame(
            up: cursor.vector4(at: HKXField(0x10, "m_up")) ?? SIMD4(),
            forward: cursor.vector4(at: HKXField(0x20, "m_forward")) ?? SIMD4(),
            duration: cursor.float32(at: HKXField(0x30, "m_duration")) ?? 0,
            samples: samples,
            unresolved: cursor.unresolved
        )
    }

    public var summary: String {
        "\(samples.count) samples over \(duration) s"
    }
}

/// Decoded `hkaInterleavedUncompressedAnimation`, size 88: every frame stored as
/// whole bone transforms, track by track inside each frame.
nonisolated public struct HKAInterleavedUncompressedAnimation: HKBClass, Equatable, Sendable {
    public let duration: Float
    public let transformTrackCount: Int
    public let floatTrackCount: Int
    public let transforms: [HKQsTransform]
    public let floats: [Float]
    public let annotationTracks: [HKAAnnotationTrack]
    public let unresolved: [HKXUnresolvedReference]

    public static let className = "hkaInterleavedUncompressedAnimation"

    public static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> HKAInterleavedUncompressedAnimation?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        let transforms = cursor.structArray(
            at: HKXField(0x38, "m_transforms"), stride: HKQsTransform.stride
        ) { element, index in
            HKQsTransform.decode(&element, at: 0, named: "m_transforms[\(index)]")
        }
        return HKAInterleavedUncompressedAnimation(
            duration: cursor.float32(at: HKXField(0x14, "m_duration")) ?? 0,
            transformTrackCount: cursor.int32(at: HKXField(0x18, "m_numberOfTransformTracks"))
                ?? 0,
            floatTrackCount: cursor.int32(at: HKXField(0x1C, "m_numberOfFloatTracks")) ?? 0,
            transforms: transforms,
            floats: cursor.float32Array(at: HKXField(0x48, "m_floats")) ?? [],
            annotationTracks: HKAAnnotationTrack.tracks(cursor: &cursor),
            unresolved: cursor.unresolved
        )
    }

    /// Frames in the clip; the transforms hold one per track per frame.
    public var frameCount: Int {
        transformTrackCount > 0 ? transforms.count / transformTrackCount : 0
    }

    public var summary: String {
        "\(transformTrackCount) tracks, \(frameCount) frames over \(duration) s"
    }
}

/// An `hkaAnnotationTrack` a tagfile stores as its own object, not inside its clip.
nonisolated public struct HKAAnnotationTrackObject: HKBClass, Equatable, Sendable {
    public let track: HKAAnnotationTrack
    public let unresolved: [HKXUnresolvedReference]

    public static let className = "hkaAnnotationTrack"

    public static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> HKAAnnotationTrackObject?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        let track = HKAAnnotationTrack.track(cursor: &cursor)
        return HKAAnnotationTrackObject(track: track, unresolved: cursor.unresolved)
    }

    public var summary: String {
        "\(track.name ?? "<unnamed track>"): \(track.annotations.count) annotations"
    }
}
