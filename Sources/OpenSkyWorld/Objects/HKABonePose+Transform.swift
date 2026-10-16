// A node's model-frame matrix as the bone pose a node rig publishes, for the cart
// wheels and the sequence doors.

import OpenSkyFormatsAnimation
import simd

nonisolated extension HKABonePose {
    /// Rotation, uniform scale, and translation of `transform`. A shear is dropped.
    init(transform: float4x4) {
        let axes = (
            SIMD3(transform.columns.0.x, transform.columns.0.y, transform.columns.0.z),
            SIMD3(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z),
            SIMD3(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)
        )
        let scale = simd_length(axes.0)
        let rotation = scale > 0
            ? simd_quatf(float3x3(axes.0 / scale, axes.1 / scale, axes.2 / scale))
            : simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        self.init(
            translation: SIMD3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z),
            rotation: rotation,
            scale: SIMD3(repeating: scale)
        )
    }
}
