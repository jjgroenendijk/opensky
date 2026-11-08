import simd

/// Where a sandbox may look for furniture, and which kinds it may use.
nonisolated public struct SandboxSeatRequest: Equatable, Sendable {
    public let center: SIMD3<Float>
    public let radius: Float
    /// Below and above the centre, as `fSandboxCylinderBottom` and `...Top`.
    public let height: ClosedRange<Float>
    /// Allow Sitting: sit and lean markers.
    public let sits: Bool
    /// Allow Sleeping: bed markers.
    public let sleeps: Bool
    /// Allow Special Furniture: crafting stations and the like.
    public let usesSpecialFurniture: Bool

    public init(
        center: SIMD3<Float>, radius: Float, height: ClosedRange<Float>,
        sits: Bool, sleeps: Bool, usesSpecialFurniture: Bool
    ) {
        self.center = center
        self.radius = radius
        self.height = height
        self.sits = sits
        self.sleeps = sleeps
        self.usesSpecialFurniture = usesSpecialFurniture
    }

    /// Whether this sandbox may use the seat: inside the area, of an allowed type, and
    /// not on furniture that is Ignored By Sandbox.
    public func admits(_ seat: FurnitureSeat) -> Bool {
        let offset = seat.position - center
        guard
            simd_length(SIMD2(offset.x, offset.y)) <= radius,
            height.contains(offset.z),
            !seat.rules.ignoredBySandbox
        else { return false }
        return seat.animationType == FurnitureSeat.sleepAnimation ? sleeps : sits
    }
}
