// NPC entry point over WalkController's existing player update path
// (issue #423). Kept outside the controller body for the lint size cap.

extension WalkController {
    /// Advances a non-player capsule on the same accumulator and fixed clock
    /// as walk mode. The temporary camera contributes facing only; all input
    /// axes are zero and the path follower supplies the displacement planner.
    mutating func update(
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
