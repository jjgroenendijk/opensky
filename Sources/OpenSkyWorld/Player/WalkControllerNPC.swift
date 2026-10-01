// NPC entry point over WalkController's player update path, kept apart for the size cap.

import OpenSkyRendering

extension WalkController {
    /// Advances a non-player capsule on the same accumulator and fixed clock
    /// as walk mode. The temporary camera contributes facing only; all input
    /// axes are zero and the path follower supplies the displacement planner.
    public mutating func update(
        frameTime: Float,
        yaw: Float,
        sampleGround: GroundSampler,
        collisionQuery: CollisionQuery = { _ in [] },
        plan: @escaping StepPlanner
    ) {
        var facing = FreeFlyCamera(position: cameraPosition, yaw: yaw, pitch: 0)
        update(
            camera: &facing,
            input: CameraInput(dt: frameTime),
            sampleGround: sampleGround,
            collisionQuery: collisionQuery,
            plan: plan
        )
    }
}
