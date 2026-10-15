// A script's change to the loaded interior's fog, from `Cell.SetFogColor`, `SetFogPlanes`,
// and `SetFogPower`. It holds while the scene keeps the lighting it was made from, so a
// different cell drops it. See docs/engine/papyrus-world-reads.md.

import Foundation

nonisolated public struct InteriorFogOverride: Equatable, Sendable {
    public let base: RenderLighting
    public private(set) var fog: FogParameters

    public init(base: RenderLighting) {
        self.base = base
        fog = base.fog ?? FogParameters(
            nearColor: .zero, farColor: .zero, nearDistance: 0, farDistance: 0, power: 1, maximum: 1
        )
    }

    public mutating func setColours(near: SIMD3<Float>, far: SIMD3<Float>) {
        fog = FogParameters(
            nearColor: near, farColor: far, nearDistance: fog.nearDistance,
            farDistance: fog.farDistance, power: fog.power, maximum: fog.maximum
        )
    }

    /// The wiki says a near plane past the far one swaps the two.
    public mutating func setPlanes(near: Float, far: Float) {
        fog = FogParameters(
            nearColor: fog.nearColor, farColor: fog.farColor, nearDistance: max(0, min(near, far)),
            farDistance: max(near, far), power: fog.power, maximum: fog.maximum
        )
    }

    public mutating func setPower(_ power: Float) {
        fog = FogParameters(
            nearColor: fog.nearColor, farColor: fog.farColor, nearDistance: fog.nearDistance,
            farDistance: fog.farDistance, power: max(0.01, power), maximum: fog.maximum
        )
    }

    /// The fog to draw under `lighting`, or nil when this override does not apply to it.
    public func fog(for lighting: RenderLighting?) -> FogParameters? {
        guard lighting == base, fog.farDistance > fog.nearDistance else { return nil }
        return fog
    }
}
