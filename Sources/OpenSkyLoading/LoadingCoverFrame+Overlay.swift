// The screen-space half of a loading screen: the line of text at the bottom,
// and during the fade a dark panel that thins out over the world.

import OpenSkyRendering
import simd

nonisolated extension LoadingCoverFrame {
    /// Larger than any drawable, so the panel covers the whole view.
    static let coverSize = UISize(width: 16384, height: 16384)
    static let textWidth: Float = 900

    public var overlay: UIScene {
        var nodes: [UINode] = []
        if !drawsObject {
            nodes.append(UINode(
                anchor: .center,
                content: .marker(size: Self.coverSize, color: SIMD4(0, 0, 0, opacity))
            ))
        }
        if let text, !text.isEmpty {
            nodes.append(UINode(
                anchor: .bottom,
                offset: UIPoint(x: 0, y: -72),
                content: .label(UILabel(
                    text: text,
                    font: UIFont(pointSize: 15),
                    color: SIMD4(0.92, 0.92, 0.88, opacity),
                    maxWidth: Self.textWidth
                ))
            ))
        }
        return UIScene(nodes: nodes)
    }
}

nonisolated extension LoadingCoverFrame {
    /// The object stands on the view axis, far enough that a model of `radius`
    /// fits the view, and tilts with `pitch` so it stays centered.
    /// XNAM moves it in view axes: right, forward, up.
    public func objectTransform(
        eye: SIMD3<Float>, yaw: Float, pitch: Float, radius: Float
    ) -> float4x4 {
        let right = SIMD3<Float>(sinf(yaw), -cosf(yaw), 0)
        let tilt = simd_quatf(angle: pitch, axis: right)
        let forward = tilt.act(SIMD3(cosf(yaw), sinf(yaw), 0))
        let up = tilt.act(SIMD3(0, 0, 1))
        let distance = max(48, radius * scale * 2.5)
        let center = eye + forward * distance
            + right * translation.x + forward * translation.y + up * translation.z
        let radians = rotationDegrees * (.pi / 180)
        let spin = tilt
            * simd_quatf(angle: yaw + .pi + radians.z, axis: SIMD3(0, 0, 1))
            * simd_quatf(angle: radians.y, axis: SIMD3(0, 1, 0))
            * simd_quatf(angle: radians.x, axis: SIMD3(1, 0, 0))
        var matrix = float4x4(spin) * float4x4(diagonal: SIMD4(scale, scale, scale, 1))
        matrix.columns.3 = SIMD4(center, 1)
        return matrix
    }
}
