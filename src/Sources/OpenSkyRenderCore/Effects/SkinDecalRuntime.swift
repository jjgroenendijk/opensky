// Decals on actors: each one is kept in the frame of the bone nearest the hit, so it moves
// with that limb. The game's skin decal options set the limits. See docs/rendering/decals.md.

import Foundation
public import OpenSkyFormatsESM
public import simd

nonisolated public struct SkinDecalRuntime: Sendable {
    /// `uMaxSkinDecals` when the settings give none; unverified.
    public static let defaultLimit = 35
    /// A body is small, so a mark is at most this wide; unverified.
    public static let maximumSize: Float = 16

    /// The decals in their actors' frames. Its limits are the skin decal limits.
    public var decals = DecalRuntime()
    public private(set) var owners: [Int: ReferenceKey] = [:]
    /// The bone each decal rides; a decal without one rides its actor's feet.
    public private(set) var bones: [Int: String] = [:]

    public init() {
        decals.limit = Self.defaultLimit
    }

    /// Places `look` where a hit struck `owner`, on the nearest of `bones` (world matrices
    /// by name), facing out from that bone. Without a bone it faces out from the actor's
    /// middle and rides `ownerTransform`. Nil when off, past the frame limit, or flat.
    @discardableResult
    public mutating func place(
        _ look: DecalLook,
        on owner: ReferenceKey,
        at position: SIMD3<Float>,
        ownerTransform: float4x4,
        bones: [String: float4x4] = [:]
    ) -> Int? {
        let bone = Self.anchorBone(in: bones, near: position)
        let frame = bone?.transform ?? ownerTransform
        var outward = position - Self.origin(of: frame)
        if bone == nil || simd_length_squared(outward) < 1e-6 {
            outward = position - Self.origin(of: ownerTransform)
            outward.z = 0
        }
        guard simd_length_squared(outward) > 1e-6, abs(frame.determinant) > 1e-8
        else { return nil }
        let local = frame.inverse
        let localPosition = local * SIMD4(position, 1)
        let localNormal = local * SIMD4(simd_normalize(outward), 0)
        guard
            let id = decals.place(
                look.capped(at: Self.maximumSize),
                at: SIMD3(localPosition.x, localPosition.y, localPosition.z),
                normal: SIMD3(localNormal.x, localNormal.y, localNormal.z)
            )
        else { return nil }
        owners[id] = owner
        self.bones[id] = bone?.name
        let live = Set(decals.decals.map(\.id))
        owners = owners.filter { live.contains($0.key) }
        self.bones = self.bones.filter { live.contains($0.key) }
        return id
    }

    /// Every decal in world space, each asking its actor's frames once. A decal whose
    /// actor or bone is gone is left out.
    public func worldDecals(_ frames: (ReferenceKey) -> SkinDecalFrames?) -> [Decal] {
        var cache: [ReferenceKey: SkinDecalFrames?] = [:]
        return decals.decals.compactMap { decal in
            guard let owner = owners[decal.id] else { return nil }
            let found = cache[owner] ?? frames(owner)
            cache[owner] = found
            guard let found else { return nil }
            let frame = bones[decal.id].map { found.bones[$0] } ?? found.feet
            return frame.map { decal.transformed(by: $0) }
        }
    }

    public mutating func removeAll() {
        decals.removeAll()
        owners.removeAll()
        bones.removeAll()
    }

    /// Bones a hit can mark: the body, not weapon, camera, or effect nodes.
    static func marksBone(_ name: String) -> Bool {
        let lower = name.lowercased()
        return !Self.unmarkedBoneWords.contains { lower.contains($0) }
    }

    private static let unmarkedBoneWords = [
        "weapon", "shield", "quiver", "camera", "magic", "animobject", "root", "arrow", "bolt"
    ]

    /// The markable bone whose origin is nearest `position`.
    static func anchorBone(
        in bones: [String: float4x4], near position: SIMD3<Float>
    ) -> (name: String, transform: float4x4)? {
        bones.filter { marksBone($0.key) }
            .min { lhs, rhs in
                let left = simd_distance_squared(origin(of: lhs.value), position)
                let right = simd_distance_squared(origin(of: rhs.value), position)
                return left == right ? lhs.key < rhs.key : left < right
            }
            .map { (name: $0.key, transform: $0.value) }
    }

    private static func origin(of transform: float4x4) -> SIMD3<Float> {
        SIMD3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
    }
}

/// Where an actor's skin decals ride this frame: its feet frame and its bones in world space.
nonisolated public struct SkinDecalFrames: Sendable {
    public let feet: float4x4?
    public let bones: [String: float4x4]

    public init(feet: float4x4?, bones: [String: float4x4]) {
        self.feet = feet
        self.bones = bones
    }
}

nonisolated extension Decal {
    /// The same decal moved by `transform`.
    public func transformed(by transform: float4x4) -> Decal {
        func point(_ value: SIMD3<Float>, _ w: Float) -> SIMD3<Float> {
            let moved = transform * SIMD4(value, w)
            return SIMD3(moved.x, moved.y, moved.z)
        }
        return Decal(
            id: id, look: look, center: point(center, 1), axisU: point(axisU, 0),
            axisV: point(axisV, 0), uvRect: uvRect
        )
    }
}

nonisolated extension DecalLook {
    /// The same look, at most `size` wide and high.
    public func capped(at size: Float) -> DecalLook {
        DecalLook(
            texture: texture, width: Self.capped(width, size), height: Self.capped(height, size),
            color: color, hasSubtextures: hasSubtextures
        )
    }

    private static func capped(_ range: ClosedRange<Float>, _ size: Float) -> ClosedRange<Float> {
        min(range.lowerBound, size) ... min(range.upperBound, size)
    }
}
