// The lockpicking menu's two meshes from the install: parsed off the main actor, then
// given GPU buffers and textures on the first frame after. Kept while the session runs.
// See docs/engine/locks.md.

import Foundation
@preconcurrency import Metal
import OpenSkyFormatsMesh
import OpenSkyGameData
import OpenSkyRendering
import simd

public final class LockpickingLockSource {
    public struct Models {
        public let lock: MenuSceneModel
        public let pick: MenuSceneModel
        /// The time in `Rotate` where the cylinder has turned furthest: the open lock.
        public let openSeconds: Float
    }

    static let paths = [LockpickingLockPose.lockPath, LockpickingLockPose.pickPath]
    /// The cylinder node that `Rotate` turns.
    static let cylinderNode = "LockPickLockTumble"

    private let loader: MenuSceneModelLoader
    public private(set) var models: Models?

    /// `immediate` loads inside the request, for tests and tools.
    public init(fileSystem: any GameFileSource, immediate: Bool = false) {
        loader = MenuSceneModelLoader(
            paths: Self.paths, fileSystem: fileSystem, immediate: immediate
        )
    }

    public var failure: String? {
        loader.failure
    }

    /// The models once both files are in; nil while they load or after a failure.
    public func models(device: MTLDevice) -> Models? {
        if let models {
            return models
        }
        guard let built = loader.models(device: device) else { return nil }
        models = Models(lock: built[0], pick: built[1], openSeconds: Self.openSeconds(built[0]))
        return models
    }

    /// The scene for one frame of `pose`, drawn over the world.
    public static func scene(_ pose: LockpickingLockPose, models: Models) -> MenuScene {
        var scene = MenuScene(
            eye: LockpickingLockCamera.eye, target: LockpickingLockCamera.target,
            up: LockpickingLockCamera.up, fovYRadians: LockpickingLockCamera.fovYRadians
        )
        scene.frontDepthSlice = LockpickingLockCamera.depthSlice
        let lock = models.lock
        let lockPose = NIFEffectPose(scene: lock.scene, playing: pose.lockPlaying(
            intro: lock.sequence(LockpickingLockPose.introSequence),
            turn: lock.sequence(LockpickingLockPose.turnSequence),
            turnSeconds: models.openSeconds
        ))
        let pick = models.pick
        var pickPose = NIFEffectPose(scene: pick.scene, playing: pose.pickPlaying(
            intro: pick.sequence(LockpickingLockPose.introSequence),
            strain: pick.sequence(LockpickingLockPose.strainSequence),
            broken: pose.brokenSeconds == nil ? nil : pick
                .sequence(LockpickingLockPose.breakSequence)
        ))
        if let node = pick.scene.node(named: LockpickingLockPose.pickNode) {
            pickPose.setLocal(
                LockpickingLockPose.turnedPick(
                    pickPose.locals[node],
                    angleDegrees: pose.pickTurnDegrees
                ),
                of: node
            )
        }
        let identity = matrix_identity_float4x4
        scene.draws = lock.draws(pose: lockPose, placement: identity, eye: scene.eye, up: scene.up)
            + pick.draws(pose: pickPose, placement: identity, eye: scene.eye, up: scene.up)
        return scene
    }

    /// Samples `Rotate` at 30 frames a second for the cylinder's largest turn from rest.
    static func openSeconds(_ model: MenuSceneModel) -> Float {
        guard
            let turn = model.sequence(LockpickingLockPose.turnSequence),
            let node = model.scene.node(named: cylinderNode)
        else { return 0 }
        let rest = simd_quatf(model.scene.restTransform(of: node))
        var best: (seconds: Float, angle: Float) = (turn.duration, 0)
        for frame in 0 ... Int((turn.duration * 30).rounded(.down)) {
            let seconds = Float(frame) / 30
            let pose = NIFEffectPose(scene: model.scene, playing: [.init(turn, seconds: seconds)])
            let angle = (simd_quatf(pose.locals[node]) * rest.inverse).angle
            let unwrapped = min(angle, 2 * .pi - angle)
            if unwrapped > best.angle + 0.0001 {
                best = (seconds, unwrapped)
            }
        }
        return best.seconds
    }
}
