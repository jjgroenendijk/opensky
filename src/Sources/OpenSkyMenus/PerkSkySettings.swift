// The `fStats` game settings that shape the perk sky. `Skyrim.esm` stores four of
// them; the rest default to the game binary's values where their meaning is known,
// and to OpenSky's own values otherwise. See docs/engine/perk-sky.md.

import Foundation

nonisolated public struct PerkSkySettings: Equatable, Sendable {
    /// `fStatsCameraFOV`, degrees.
    public var cameraFOV: Float = 50
    /// `fStatsStarXIncrement`, `fStatsStarYIncrement`, `fStatsStarZIncrement`: the
    /// offset of one grid step across, one step up, and the depth per step up.
    public var starIncrement: SIMD3<Float> = [5, 15, -9]
    /// `fStatsStarZInitialOffset`: how far a tree's bottom row stands toward the camera.
    public var starZInitialOffset: Float = 5
    /// `fStatsStarScale`, and `fStatsLineScale` for a line's width.
    public var starScale: Float = 0.15
    public var lineScale: Float = 0.1175
    /// The factor on the up and depth steps, measured on vanilla screenshots; no
    /// setting names it.
    var rowScale: Float = 0.43
    /// `fStatsRotationSpeedMax` in turns per second: the binary's 0.5 is the 180 degrees a
    /// second seen on footage. `fStatsRotationRampTime` in milliseconds; 250 is ours, as
    /// the binary's 2000 would turn one slot in 0.67 s, not the 0.2 s seen.
    public var rotationSpeedMax: Float = 0.5
    public var rotationRampTime: Float = 250

    /// The turn speed in degrees per second, and the ramp in seconds.
    var rotationDegreesPerSecond: Float {
        rotationSpeedMax * 360
    }

    var rotationRampSeconds: Float {
        rotationRampTime / 1000
    }

    /// `fStatsSkillsLookAt`: where the ring camera looks. Vectors here are in the frame
    /// of the skill ahead: +X right, +Y out to its star, +Z up.
    public var skillsLookAt: SIMD3<Float> = [0, 100, 10]
    /// `fStatsStarLookAt` and `fStatsStarCameraOffset`: the tree camera.
    public var starLookAt: SIMD3<Float> = [0, 95, 15]
    public var starCameraOffset: SIMD3<Float> = [0, 45, 12]

    init() {}

    /// Values from the load order where it has them.
    public init(setting: (String) -> Float?) {
        cameraFOV = setting("fStatsCameraFOV") ?? cameraFOV
        starIncrement = [
            setting("fStatsStarXIncrement") ?? starIncrement.x,
            setting("fStatsStarYIncrement") ?? starIncrement.y,
            setting("fStatsStarZIncrement") ?? starIncrement.z
        ]
        starZInitialOffset = setting("fStatsStarZInitialOffset") ?? starZInitialOffset
        starScale = setting("fStatsStarScale") ?? starScale
        lineScale = setting("fStatsLineScale") ?? lineScale
        rotationSpeedMax = setting("fStatsRotationSpeedMax") ?? rotationSpeedMax
        rotationRampTime = setting("fStatsRotationRampTime") ?? rotationRampTime
        skillsLookAt = Self.vector("fStatsSkillsLookAt", setting) ?? skillsLookAt
        starLookAt = Self.vector("fStatsStarLookAt", setting) ?? starLookAt
        starCameraOffset = Self.vector("fStatsStarCameraOffset", setting) ?? starCameraOffset
    }

    private static func vector(_ name: String, _ setting: (String) -> Float?) -> SIMD3<Float>? {
        guard let x = setting(name + "X"), let y = setting(name + "Y"), let z = setting(name + "Z")
        else { return nil }
        return [x, y, z]
    }
}
