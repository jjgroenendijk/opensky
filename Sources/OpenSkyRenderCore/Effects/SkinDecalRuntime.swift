// Decals on actors: each one is kept in its actor's own frame, so it moves with the
// actor. The game's skin decal options set the limits. See docs/rendering/decals.md.

import Foundation
import OpenSkyFormatsESM
import simd

nonisolated public struct SkinDecalRuntime: Sendable {
    /// `uMaxSkinDecals` when the settings give none; unverified.
    public static let defaultLimit = 35
    /// A body is small, so a mark is at most this wide; unverified.
    public static let maximumSize: Float = 16

    /// The decals in their actors' frames. Its limits are the skin decal limits.
    public var decals = DecalRuntime()
    public private(set) var owners: [Int: ReferenceKey] = [:]

    public init() {
        decals.limit = Self.defaultLimit
    }

    /// Places `look` where a hit struck `owner`, facing out from the actor's middle.
    /// Nil when skin decals are off, the frame limit is reached, or the frame is flat.
    @discardableResult
    public mutating func place(
        _ look: DecalLook,
        on owner: ReferenceKey,
        at position: SIMD3<Float>,
        ownerTransform: float4x4
    ) -> Int? {
        let origin = SIMD3(
            ownerTransform.columns.3.x, ownerTransform.columns.3.y, ownerTransform.columns.3.z
        )
        var outward = position - origin
        outward.z = 0
        guard simd_length_squared(outward) > 1e-6, abs(ownerTransform.determinant) > 1e-8
        else { return nil }
        let local = ownerTransform.inverse
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
        let live = Set(decals.decals.map(\.id))
        owners = owners.filter { live.contains($0.key) }
        return id
    }

    /// Every decal in world space; a decal whose actor has no transform is left out.
    public func worldDecals(_ transform: (ReferenceKey) -> float4x4?) -> [Decal] {
        decals.decals.compactMap { decal in
            guard let owner = owners[decal.id], let frame = transform(owner) else { return nil }
            return decal.transformed(by: frame)
        }
    }

    public mutating func removeAll() {
        decals.removeAll()
        owners.removeAll()
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
