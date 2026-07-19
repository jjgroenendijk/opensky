// Camera + light parameters the renderer folds into FrameUniforms (todo 2.7
// app wiring). Decouples Renderer from DemoScene: the app injects a framing
// camera for a built cell; `demo` mirrors the DemoScene constants for the
// synthetic fallback scene.

import simd

nonisolated struct SceneCamera {
    let eye: SIMD3<Float>
    let target: SIMD3<Float>
    /// Direction sunlight travels (unit vector).
    let sunDirection: SIMD3<Float>
    let sunColor: SIMD3<Float>
    let ambientColor: SIMD3<Float>
    /// Actor-origin pose for an XTEL camera. Free-fly uses `eye` verbatim;
    /// walk mode raises this feet position by capsule eye height.
    let walkFeetPosition: SIMD3<Float>?

    init(
        eye: SIMD3<Float>,
        target: SIMD3<Float>,
        sunDirection: SIMD3<Float>,
        sunColor: SIMD3<Float>,
        ambientColor: SIMD3<Float>,
        walkFeetPosition: SIMD3<Float>? = nil
    ) {
        self.eye = eye
        self.target = target
        self.sunDirection = sunDirection
        self.sunColor = sunColor
        self.ambientColor = ambientColor
        self.walkFeetPosition = walkFeetPosition
    }

    /// DemoScene's hand-tuned camera + light — used whenever no cell scene
    /// is injected (existing tests, missing game data).
    static let demo = SceneCamera(
        eye: DemoScene.cameraEye,
        target: DemoScene.cameraTarget,
        sunDirection: DemoScene.sunDirection,
        sunColor: DemoScene.sunColor,
        ambientColor: DemoScene.ambientColor
    )

    /// Vertical fov the renderer projects with — framing distance derives
    /// from it so the framed box fits on screen at any aspect >= 1.
    private static let fovYRadians = MatrixMath.radians(fromDegrees: 65)

    /// Eye offset direction from the bounds center: south-west (-x, -y) and
    /// above (+z), matching the demo vantage. The demo sun sits in the
    /// south-west sky, so faces toward this camera are the lit ones.
    private static let eyeDirection = simd_normalize(SIMD3<Float>(-1, -1, 0.7))

    /// Frames a Z-up world AABB: target = box center, eye pushed along
    /// `eyeDirection` far enough that the sphere enclosing the box fits the
    /// vertical fov (radius / sin(fov / 2)), with a 1.1 margin so silhouettes
    /// clear the frame edge. Sun/ambient reuse the demo values. Degenerate
    /// (near-point) bounds fall back to a minimum distance so the camera
    /// never sits on its target.
    static func framing(bounds: (min: SIMD3<Float>, max: SIMD3<Float>)) -> SceneCamera {
        let center = (bounds.min + bounds.max) * 0.5
        let radius = simd_length(bounds.max - bounds.min) * 0.5
        let fitDistance = radius / sinf(fovYRadians * 0.5) * 1.1
        // 64 units ~ 0.9 m (docs/decisions/coordinates.md scale) — clears the
        // 10-unit near plane with room to spare.
        let distance = max(fitDistance, 64)
        return SceneCamera(
            eye: center + eyeDirection * distance,
            target: center,
            sunDirection: DemoScene.sunDirection,
            sunColor: DemoScene.sunColor,
            ambientColor: DemoScene.ambientColor
        )
    }

    /// Creates an XTEL arrival pose. Skyrim rotation X is pitch, Z is heading
    /// in same Z-up basis used by REFR transforms; Y roll is intentionally
    /// ignored by upright free-fly view.
    static func teleport(placement: PlacedReference.Placement) -> SceneCamera {
        let yaw = placement.rotation.z
        let pitch = placement.rotation.x
        let cosPitch = cosf(pitch)
        let forward = SIMD3<Float>(
            cosPitch * cosf(yaw),
            cosPitch * sinf(yaw),
            sinf(pitch)
        )
        return SceneCamera(
            eye: placement.position,
            target: placement.position + forward,
            sunDirection: demo.sunDirection,
            sunColor: demo.sunColor,
            ambientColor: demo.ambientColor,
            walkFeetPosition: placement.position
        )
    }
}
