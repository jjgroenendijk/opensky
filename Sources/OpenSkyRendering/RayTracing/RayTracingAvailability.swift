// Whether this GPU can run the ray-traced effects. Hardware ray tracing starts with the
// Apple9 family (M3); M1 and M2 trace rays in software, which is too slow per pixel.
// See docs/rendering/ray-traced-shadows.md.

import Metal

nonisolated public enum RayTracingAvailability: Equatable, Sendable {
    case available
    case unavailable(reason: String)

    public static let softwareReason = "Needs an M3 or later GPU; this one traces rays in software"
    public static let missingReason = "This GPU cannot trace rays"

    public static func check(supportsRayTracing: Bool, hardwareRayTracing: Bool) -> Self {
        guard supportsRayTracing else { return .unavailable(reason: missingReason) }
        guard hardwareRayTracing else { return .unavailable(reason: softwareReason) }
        return .available
    }

    public static func of(_ device: MTLDevice?) -> Self {
        guard let device else { return .unavailable(reason: missingReason) }
        return check(
            supportsRayTracing: device.supportsRaytracing,
            hardwareRayTracing: device.supportsFamily(.apple9)
        )
    }

    public var isAvailable: Bool {
        self == .available
    }

    public var reason: String? {
        if case let .unavailable(reason) = self {
            return reason
        }
        return nil
    }
}
