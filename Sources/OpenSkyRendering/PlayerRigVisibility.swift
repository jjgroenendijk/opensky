// Which of the player's two rigs is drawn and which casts a shadow, as one testable
// value. The body casts in every mode, so a first-person player has a shadow; the arms
// never cast, because they hang off the camera. A stated policy, not a measurement
// (docs/engine/first-person.md).

nonisolated public struct PlayerRigVisibility: Equatable, Sendable {
    /// The third-person body is drawn to the camera.
    public let drawsBody: Bool
    /// The third-person body is rasterized into the shadow map.
    public let castsBodyShadow: Bool
    /// The first-person arms are drawn to the camera.
    public let drawsArms: Bool
    /// The first-person arms are rasterized into the shadow map. Always false;
    /// carried as a field so the matrix is complete and the test can pin it.
    public let castsArmShadow: Bool

    /// The rig policy for `mode`. `armsEnabled` is the panel toggle. In a conversation
    /// the arms hide, and a first-person body stays hidden: the eye sits just behind
    /// the head, so the head and helmet would fill the view, and the game hides them too.
    public static func resolve(
        mode: CameraMovementMode,
        hasBody: Bool,
        hasArms: Bool,
        armsEnabled: Bool = true,
        dialogueCamera: Bool = false
    ) -> PlayerRigVisibility {
        // Fly draws the body so a developer can fly around the character and
        // look at it; first person hides it because the eye is inside its head.
        let firstPerson = mode == .walk && !dialogueCamera
        let bodyVisible = hasBody && mode != .walk
        return PlayerRigVisibility(
            drawsBody: bodyVisible,
            castsBodyShadow: hasBody && (mode.isPlayerControlled || bodyVisible),
            drawsArms: hasArms && armsEnabled && firstPerson,
            castsArmShadow: false
        )
    }
}
