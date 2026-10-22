// The 3D lock of the lockpicking menu: which sequence of the install's lock and pick
// meshes plays at which time, the turn of the pick by its angle, and the camera.
// Pure, so tests drive it. See docs/engine/locks.md.

import OpenSkyFormatsMesh
import simd

/// One frame of the 3D lock, from the menu's presentation and its clock.
nonisolated public struct LockpickingLockPose: Equatable, Sendable {
    /// The lock, its cylinder (`LockPickLockTumble`), and the shiv that turns it.
    public static let lockPath = "meshes\\interface\\lockpicking\\lockpickshiv01.nif"
    public static let pickPath = "meshes\\interface\\lockpicking\\lockpick01.nif"
    /// The node the engine turns about the keyhole by the pick angle.
    public static let pickNode = "LockPick01"
    public static let introSequence = "Intro"
    public static let turnSequence = "Rotate"
    public static let strainSequence = "PickDamage"
    public static let breakSequence = "PickBreak"
    /// `Rotate` turns the cylinder a quarter turn, clockwise on screen, by the open lock.
    public static let cylinderTurnDegrees: Float = 90
    /// The part of `PickBreak` in which the broken pick flies off; it rests after that.
    public static let breakSeconds: Float = 0.7

    /// Seconds since the menu opened, or since the last fresh pick went in.
    public var pickSeconds: Float
    public var lockSeconds: Float
    public var pickAngle: Float
    /// 0 at rest, 1 open.
    public var lockRotation: Float
    public var isStraining: Bool
    /// Seconds since the last pick broke, while its flight shows.
    public var brokenSeconds: Float?

    public init(
        pickSeconds: Float, lockSeconds: Float, pickAngle: Float, lockRotation: Float,
        isStraining: Bool, brokenSeconds: Float? = nil
    ) {
        self.pickSeconds = pickSeconds
        self.lockSeconds = lockSeconds
        self.pickAngle = pickAngle
        self.lockRotation = lockRotation
        self.isStraining = isStraining
        self.brokenSeconds = brokenSeconds
    }

    /// The pick sits in the cylinder, so it turns with it on top of its own angle.
    public var pickTurnDegrees: Float {
        pickAngle + simd_clamp(lockRotation, 0, 1) * Self.cylinderTurnDegrees
    }

    /// What the lock mesh plays: its intro, then `Rotate` held at the lock's turn.
    /// `turnSeconds` is the time in `Rotate` where the cylinder is fully open.
    public func lockPlaying(
        intro: NIFSequence?, turn: NIFSequence?, turnSeconds: Float
    ) -> [NIFEffectPose.Playing] {
        if let intro, lockSeconds < intro.duration {
            return [.init(intro, seconds: lockSeconds)]
        }
        guard let turn else { return intro.map { [.init($0, seconds: $0.duration)] } ?? [] }
        let rotation = simd_clamp(lockRotation, 0, 1)
        return [.init(turn, seconds: rotation * turnSeconds)]
    }

    /// What the pick mesh plays: its intro, a jiggle while straining, and the break.
    public func pickPlaying(
        intro: NIFSequence?, strain: NIFSequence?, broken: NIFSequence?
    ) -> [NIFEffectPose.Playing] {
        if let brokenSeconds, let broken {
            return [.init(broken, seconds: min(brokenSeconds, Self.breakSeconds))]
        }
        var playing = intro.map { [NIFEffectPose.Playing($0, seconds: pickSeconds)] } ?? []
        if isStraining, let strain {
            let seconds = pickSeconds.truncatingRemainder(dividingBy: max(strain.duration, 0.01))
            playing.append(.init(strain, seconds: seconds))
        }
        return playing
    }

    /// The pick's local transform turned by the pick angle about the view axis (+Y)
    /// through the pick's own origin, which sits in the keyhole once the intro ends.
    public static func turnedPick(_ local: float4x4, angleDegrees: Float) -> float4x4 {
        let pivot = SIMD3(local.columns.3.x, local.columns.3.y, local.columns.3.z)
        let turn = float4x4(simd_quatf(angle: angleDegrees * .pi / 180, axis: SIMD3(0, 1, 0)))
        return translation(pivot) * turn * translation(-pivot) * local
    }

    private static func translation(_ offset: SIMD3<Float>) -> float4x4 {
        var matrix = matrix_identity_float4x4
        matrix.columns.3 = SIMD4(offset, 1)
        return matrix
    }
}

/// The menu camera: in front of the keyhole on -Y, looking along +Y with +Z up.
/// The game's camera is not in the meshes; these numbers are OpenSky's framing.
nonisolated public enum LockpickingLockCamera {
    public static let target = SIMD3<Float>(14.5, -16, 2)
    public static let eye = SIMD3<Float>(14.5, -420, 60)
    public static let up = SIMD3<Float>(0, 0, 1)
    public static let fovYRadians: Float = 34 * .pi / 180
    /// The depth share the lock draws into, as the inventory item does.
    public static let depthSlice: Float = 0.005
}
