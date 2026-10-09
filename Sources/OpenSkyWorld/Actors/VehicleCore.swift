// Vehicles: a cart tethered to its horse, and riders sitting on the cart. A
// follower keeps the offset it had to its carrier when it was attached, so it
// moves as the carrier moves (<https://ck.uesp.net/wiki/SetVehicle_-_Actor>).

import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyWorldState
import simd

/// One follower's carrier and its fixed offset from the carrier.
nonisolated public struct VehicleLink: Equatable, Sendable {
    public let carrier: ReferenceKey
    public let offset: float4x4
}

nonisolated public struct VehicleCore: Equatable, Sendable {
    /// The cart exit idles send this when the rider stands beside the cart, which
    /// takes it off the vehicle. See docs/engine/vehicles.md.
    public static let exitEvent = "ExitCartEnd"
    /// A chain longer than this is a loop in plugin or script data.
    private static let maximumDepth = 8

    public private(set) var links: [ReferenceKey: VehicleLink] = [:]

    public init() {}

    /// False when the link would make a loop.
    @discardableResult
    public mutating func attach(
        _ follower: ReferenceKey,
        to carrier: ReferenceKey,
        followerPose: ReferenceTransformOverride,
        carrierPose: ReferenceTransformOverride
    ) -> Bool {
        guard follower != carrier, !carries(follower, carrier) else { return false }
        links[follower] = VehicleLink(
            carrier: carrier,
            offset: Self.matrix(carrierPose).inverse * Self.matrix(followerPose)
        )
        return true
    }

    public mutating func detach(_ follower: ReferenceKey) {
        links[follower] = nil
    }

    /// Every follower's live pose. `base` answers for a reference that follows
    /// nothing, such as the horse that pulls the cart.
    public func poses(
        base: (ReferenceKey) -> ReferenceTransformOverride?
    ) -> [ReferenceKey: ReferenceTransformOverride] {
        var result: [ReferenceKey: ReferenceTransformOverride] = [:]
        for follower in links.keys.sorted() {
            if let matrix = pose(of: follower, base: base, depth: 0) {
                result[follower] = Self.transform(matrix)
            }
        }
        return result
    }

    private func pose(
        of key: ReferenceKey,
        base: (ReferenceKey) -> ReferenceTransformOverride?,
        depth: Int
    ) -> float4x4? {
        guard let link = links[key] else { return base(key).map(Self.matrix) }
        guard depth < Self.maximumDepth else { return nil }
        return pose(of: link.carrier, base: base, depth: depth + 1).map { $0 * link.offset }
    }

    /// True when `follower` is somewhere above `carrier` in its chain.
    private func carries(_ follower: ReferenceKey, _ carrier: ReferenceKey) -> Bool {
        var current = links[carrier]?.carrier
        var depth = 0
        while let next = current, depth < Self.maximumDepth {
            if next == follower {
                return true
            }
            current = links[next]?.carrier
            depth += 1
        }
        return false
    }

    static func matrix(_ pose: ReferenceTransformOverride) -> float4x4 {
        MatrixMath.placement(position: pose.position, rotation: pose.rotation, scale: 1)
    }

    static func transform(_ matrix: float4x4) -> ReferenceTransformOverride {
        let rotation = float3x3(
            SIMD3(matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z),
            SIMD3(matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z),
            SIMD3(matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z)
        )
        return ReferenceTransformOverride(
            position: SIMD3(matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z),
            rotation: MatrixMath.eulerAngles(of: simd_quatf(rotation))
        )
    }
}
