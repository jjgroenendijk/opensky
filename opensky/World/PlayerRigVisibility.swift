// Which of the player's two rigs is drawn, and which is cast (issue #190).
//
// The matrix is a value rather than four scattered `movementMode ==` checks in
// the renderer, because the four answers are one policy and reading them apart
// is how a mode ends up drawing both rigs or neither. Being a plain value also
// makes the policy testable without a Metal device, which the renderer's own
// draw lists are not.
//
// **Shadows.** The body casts in every mode a player exists in, including the
// first-person mode that hides it from the camera, so a first-person player has
// a shadow on the ground in front of them. Vanilla's renderer is not observable
// from the install, so this is a stated policy and not a measurement: what
// decides it is that a shadow which appeared and vanished with a camera key
// would be an artefact of the camera, and nothing else in this world is. The
// arms never cast. They hang off the camera rather than standing in the world,
// so their shadow would be a disembodied pair of arms sliding over the terrain.
// Recorded in docs/engine/behavior-runtime.md, "First person".

nonisolated struct PlayerRigVisibility: Equatable {
    /// The third-person body is drawn to the camera.
    let drawsBody: Bool
    /// The third-person body is rasterized into the shadow map.
    let castsBodyShadow: Bool
    /// The first-person arms are drawn to the camera.
    let drawsArms: Bool
    /// The first-person arms are rasterized into the shadow map. Always false;
    /// carried as a field so the matrix is complete and the test can pin it.
    let castsArmShadow: Bool

    /// - Parameters:
    ///   - mode: the active camera.
    ///   - hasBody: a third-person body is assembled and attached.
    ///   - hasArms: a first-person rig is assembled and attached.
    ///   - armsEnabled: the panel's arms A/B toggle.
    static func resolve(
        mode: CameraMovementMode,
        hasBody: Bool,
        hasArms: Bool,
        armsEnabled: Bool = true
    ) -> PlayerRigVisibility {
        // Fly draws the body so a developer can fly around the character and
        // look at it; first person hides it because the eye is inside its head.
        let bodyVisible = hasBody && mode != .walk
        return PlayerRigVisibility(
            drawsBody: bodyVisible,
            castsBodyShadow: hasBody && (mode.isPlayerControlled || bodyVisible),
            drawsArms: hasArms && armsEnabled && mode == .walk,
            castsArmShadow: false
        )
    }
}
