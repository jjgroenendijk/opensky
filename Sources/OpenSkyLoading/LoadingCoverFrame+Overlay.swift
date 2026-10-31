// The screen-space half of a loading screen: the line of text at the bottom,
// and during the fade a dark panel that thins out over the world. Also where
// the object stands and how it is lit. See docs/engine/loading-screens.md.

import OpenSkyFormatsESM
import OpenSkyRenderCore
import simd

nonisolated extension LoadingCoverFrame {
    /// Larger than any drawable, so the panel covers the whole view.
    static let coverSize = UISize(width: 16384, height: 16384)
    static let textWidth: Float = 900

    public var overlay: UIScene {
        overlay(showsText: true)
    }

    /// `showsText` is false while the game's loading movie draws the tip.
    public func overlay(showsText: Bool) -> UIScene {
        var nodes: [UINode] = []
        if !drawsObject {
            nodes.append(UINode(
                anchor: .center,
                content: .marker(size: Self.coverSize, color: SIMD4(0, 0, 0, opacity))
            ))
        }
        if showsText, let text, !text.isEmpty {
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
    /// fits the view, and tilts with `pitch` so it stays centered. XNAM moves it
    /// in view axes (right, forward, up); `cameraOffset`, the MOD2 path's camera
    /// position in the same axes, moves the eye.
    public func objectTransform(
        eye: SIMD3<Float>, yaw: Float, pitch: Float, radius: Float,
        cameraOffset: SIMD3<Float> = .zero
    ) -> float4x4 {
        let axes = Self.viewAxes(yaw: yaw, pitch: pitch)
        // The path's back distance counts only where it is farther than the fit,
        // so the zoom stops before the camera reaches the object.
        let distance = max(48, radius * scale * 2.5, -cameraOffset.y)
        let offset = translation - SIMD3(cameraOffset.x, 0, cameraOffset.z)
        let center = eye + axes.forward * distance
            + axes.right * offset.x + axes.forward * offset.y + axes.up * offset.z
        let radians = rotationDegrees * (.pi / 180)
        let spin = axes.tilt
            * simd_quatf(angle: yaw + .pi + radians.z, axis: SIMD3(0, 0, 1))
            * simd_quatf(angle: radians.y, axis: SIMD3(0, 1, 0))
            * simd_quatf(angle: radians.x, axis: SIMD3(1, 0, 0))
        var matrix = float4x4(spin) * float4x4(diagonal: SIMD4(scale, scale, scale, 1))
        matrix.columns.3 = SIMD4(center, 1)
        return matrix
    }

    /// The cover's own light: white from above, behind the eye, and to the left,
    /// over a grey ambient, with no fog. The game's light is not documented, so
    /// these values are OpenSky's.
    public static func lighting(yaw: Float, pitch: Float) -> RenderLighting {
        let axes = viewAxes(yaw: yaw, pitch: pitch)
        let travel = simd_normalize(axes.forward + axes.right * 0.6 - axes.up * 0.8)
        let ambient = SIMD3<Float>(repeating: ambientLevel)
        return RenderLighting(
            ambientColor: ambient,
            directionalAmbient: DirectionalAmbientColors(
                positiveX: ambient, negativeX: ambient, positiveY: ambient,
                negativeY: ambient, positiveZ: ambient, negativeZ: ambient
            ),
            directionalDirection: travel,
            directionalColor: SIMD3(1, 0.97, 0.92),
            fog: nil
        )
    }

    static let ambientLevel: Float = 0.32

    nonisolated private struct ViewAxes {
        let right: SIMD3<Float>
        let forward: SIMD3<Float>
        let up: SIMD3<Float>
        let tilt: simd_quatf
    }

    private static func viewAxes(yaw: Float, pitch: Float) -> ViewAxes {
        let right = SIMD3<Float>(sinf(yaw), -cosf(yaw), 0)
        let tilt = simd_quatf(angle: pitch, axis: right)
        return ViewAxes(
            right: right, forward: tilt.act(SIMD3(cosf(yaw), sinf(yaw), 0)),
            up: tilt.act(SIMD3(0, 0, 1)), tilt: tilt
        )
    }
}
