// Vehicles: a cart towed by its horse, riders sitting on the cart, and a rider on
// a horse's saddle (<https://ck.uesp.net/wiki/SetVehicle_-_Actor>,
// <https://ck.uesp.net/wiki/TetherToHorse_-_ObjectReference>).
// See docs/engine/vehicles.md.

import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyWorldState
import simd

/// How a follower sits on its carrier.
nonisolated public enum VehicleSeat: Equatable, Sendable {
    /// A fixed pose in the carrier's frame.
    case fixed(float4x4)
    /// On a bone of the carrier's live pose, such as a horse's `SaddleBone`.
    case bone(String)
    /// Pulled along the carrier's path, as a cart behind its horse.
    case towed(VehicleTow)
}

/// A towed follower keeps its distance to the carrier and turns toward it.
nonisolated public struct VehicleTow: Equatable, Sendable {
    /// Horizontal distance from the follower's origin to the carrier's origin.
    public let length: Float
    /// The follower's orientation at the link, and the heading it had then.
    public let orientation: float3x3
    public let linkHeading: Float
    public let linkSlope: Float
    /// Height above the ground at the link, or above the carrier without ground.
    public let clearance: Float
    public let rise: Float
    public var position: SIMD3<Float>
    public var heading: Float
}

/// One follower's carrier and how it sits there.
nonisolated public struct VehicleLink: Equatable, Sendable {
    public let carrier: ReferenceKey
    public var seat: VehicleSeat
}

nonisolated public struct VehicleCore: Equatable, Sendable {
    /// The cart exit idles send this when the rider stands beside the cart, which
    /// takes it off the vehicle. See docs/engine/vehicles.md.
    public static let exitEvent = "ExitCartEnd"
    /// A chain longer than this is a loop in plugin or script data.
    private static let maximumDepth = 8

    public private(set) var links: [ReferenceKey: VehicleLink] = [:]

    public init() {}

    /// Keeps the follower's current offset to the carrier. False when the link would
    /// make a loop.
    @discardableResult
    public mutating func attach(
        _ follower: ReferenceKey,
        to carrier: ReferenceKey,
        followerPose: ReferenceTransformOverride,
        carrierPose: ReferenceTransformOverride
    ) -> Bool {
        let offset = Self.matrix(carrierPose).inverse * Self.matrix(followerPose)
        return link(follower, to: carrier, seat: .fixed(offset))
    }

    /// `SetVehicle`: a rider's root sits on the vehicle's root, and its seat idle
    /// moves the body into its seat.
    @discardableResult
    public mutating func board(_ rider: ReferenceKey, on vehicle: ReferenceKey) -> Bool {
        link(rider, to: vehicle, seat: .fixed(matrix_identity_float4x4))
    }

    /// Seats `rider` on a bone of `carrier`, facing the way the carrier faces.
    @discardableResult
    public mutating func seat(
        _ rider: ReferenceKey, on carrier: ReferenceKey, bone: String
    ) -> Bool {
        link(rider, to: carrier, seat: .bone(bone))
    }

    /// `TetherToHorse`: the follower trails the carrier at the distance it has now.
    @discardableResult
    public mutating func tow(
        _ follower: ReferenceKey,
        by carrier: ReferenceKey,
        followerPose: ReferenceTransformOverride,
        carrierPose: ReferenceTransformOverride,
        ground: (SIMD2<Float>) -> Float? = { _ in nil }
    ) -> Bool {
        let cart = followerPose.position
        let hitch = carrierPose.position
        let flat = SIMD2(hitch.x - cart.x, hitch.y - cart.y)
        let length = simd_length(flat)
        guard length > 1 else {
            return attach(
                follower, to: carrier, followerPose: followerPose, carrierPose: carrierPose
            )
        }
        let heading = atan2(flat.x, flat.y)
        let cartGround = ground(SIMD2(cart.x, cart.y))
        let matrix = Self.matrix(followerPose)
        let tow = VehicleTow(
            length: length,
            orientation: float3x3(
                SIMD3(matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z),
                SIMD3(matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z),
                SIMD3(matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z)
            ),
            linkHeading: heading,
            linkSlope: Self.slope(from: cartGround, to: ground(SIMD2(hitch.x, hitch.y)), length),
            clearance: cartGround.map { cart.z - $0 } ?? 0,
            rise: cart.z - hitch.z,
            position: cart,
            heading: heading
        )
        return link(follower, to: carrier, seat: .towed(tow))
    }

    private mutating func link(
        _ follower: ReferenceKey, to carrier: ReferenceKey, seat: VehicleSeat
    ) -> Bool {
        guard follower != carrier, !carries(follower, carrier) else { return false }
        links[follower] = VehicleLink(carrier: carrier, seat: seat)
        return true
    }

    public mutating func detach(_ follower: ReferenceKey) {
        links[follower] = nil
    }

    /// Every follower's live pose this frame. A towed follower moves along.
    /// `base` answers for a reference that follows nothing, such as the horse; `bone`
    /// gives a bone of a reference's live pose in its root frame.
    public mutating func advance(
        base: (ReferenceKey) -> ReferenceTransformOverride?,
        bone: (ReferenceKey, String) -> SIMD3<Float>? = { _, _ in nil },
        ground: (SIMD2<Float>) -> Float? = { _ in nil }
    ) -> [ReferenceKey: ReferenceTransformOverride] {
        withoutActuallyEscaping(base) { base in
            withoutActuallyEscaping(bone) { bone in
                withoutActuallyEscaping(ground) { ground in
                    var frame = Frame(base: base, bone: bone, ground: ground)
                    for follower in links.keys.sorted() {
                        _ = pose(of: follower, frame: &frame, depth: 0)
                    }
                    return frame.solved.filter { links[$0.key] != nil }.mapValues(Self.transform)
                }
            }
        }
    }

    nonisolated private struct Frame {
        let base: (ReferenceKey) -> ReferenceTransformOverride?
        let bone: (ReferenceKey, String) -> SIMD3<Float>?
        let ground: (SIMD2<Float>) -> Float?
        var solved: [ReferenceKey: float4x4] = [:]
    }

    private mutating func pose(
        of key: ReferenceKey, frame: inout Frame, depth: Int
    ) -> float4x4? {
        if let known = frame.solved[key] {
            return known
        }
        guard let link = links[key] else {
            let base = frame.base(key).map(Self.matrix)
            frame.solved[key] = base
            return base
        }
        guard
            depth < Self.maximumDepth,
            let carrier = pose(of: link.carrier, frame: &frame, depth: depth + 1)
        else { return nil }
        let result: float4x4
        switch link.seat {
        case let .fixed(offset):
            result = carrier * offset
        case let .bone(name):
            let bone = frame.bone(link.carrier, name) ?? .zero
            result = carrier * MatrixMath.translation(bone)
        case var .towed(tow):
            result = Self.pull(&tow, hitch: carrier.columns.3, ground: frame.ground)
            links[key]?.seat = .towed(tow)
        }
        frame.solved[key] = result
        return result
    }

    /// Moves a towed follower to `length` behind the hitch, along the line from where
    /// it was, so it trails the carrier's path. It sits on the ground and tilts with it.
    static func pull(
        _ tow: inout VehicleTow, hitch: SIMD4<Float>, ground: (SIMD2<Float>) -> Float?
    ) -> float4x4 {
        let flat = SIMD2(hitch.x - tow.position.x, hitch.y - tow.position.y)
        if simd_length(flat) > 0.001 {
            tow.heading = atan2(flat.x, flat.y)
        }
        let direction = SIMD2(sin(tow.heading), cos(tow.heading))
        let spot = SIMD2(hitch.x, hitch.y) - direction * tow.length
        let below = ground(spot)
        let height = below.map { $0 + tow.clearance } ?? hitch.z + tow.rise
        tow.position = SIMD3(spot.x, spot.y, height)
        let tilt = slope(from: below, to: ground(SIMD2(hitch.x, hitch.y)), tow.length)
            - tow.linkSlope
        let right = SIMD3(direction.y, -direction.x, 0)
        let turn = MatrixMath.rotation(radians: tilt, axis: right)
            * MatrixMath.rotationZ(radians: -(tow.heading - tow.linkHeading))
        let orientation = tow.orientation
        let rotation = float4x4(
            SIMD4(orientation.columns.0, 0), SIMD4(orientation.columns.1, 0),
            SIMD4(orientation.columns.2, 0), SIMD4(0, 0, 0, 1)
        )
        return MatrixMath.translation(tow.position) * turn * rotation
    }

    private static func slope(from low: Float?, to high: Float?, _ length: Float) -> Float {
        guard let low, let high, length > 0 else { return 0 }
        return atan2(high - low, length)
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
