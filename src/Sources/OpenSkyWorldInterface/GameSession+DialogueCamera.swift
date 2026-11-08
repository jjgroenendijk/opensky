import OpenSkyPhysics
import OpenSkyRenderCore
import simd

/// What the app publishes each frame while a conversation is open. Sampled by
/// the session — the renderer knows nothing about speakers, rigs or menus.
nonisolated public struct DialogueCameraFocus: Equatable, Sendable {
    /// The speaker's head, world space.
    public let headPosition: SIMD3<Float>
    /// The side the shot is taken from; nil is the player's eye.
    public let viewpoint: SIMD3<Float>?
    /// The subject is the player, as in the race menu, so the body is drawn.
    public let framesPlayer: Bool

    public init(
        headPosition: SIMD3<Float>, viewpoint: SIMD3<Float>? = nil, framesPlayer: Bool = false
    ) {
        self.headPosition = headPosition
        self.viewpoint = viewpoint
        self.framesPlayer = framesPlayer
    }
}
