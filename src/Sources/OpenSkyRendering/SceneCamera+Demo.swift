public import OpenSkyRenderCore

nonisolated extension SceneCamera {
    /// DemoScene's hand-tuned camera + light — used whenever no cell scene
    /// is injected (existing tests, missing game data).
    public static let demo = SceneCamera(
        eye: DemoScene.cameraEye,
        target: DemoScene.cameraTarget,
        sunDirection: DemoScene.sunDirection,
        sunColor: DemoScene.sunColor,
        ambientColor: DemoScene.ambientColor
    )
}
