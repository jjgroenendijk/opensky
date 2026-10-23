// Main-app seam for the dialogue camera and speaker focus, shaped like
// `DialogueControlProviding`. The force toggle frames any selected actor, so
// framing, collision pull-in, and speaker turn can be checked without a
// conversation (docs/engine/dialogue-camera.md).

import simd

/// Which actor the force toggle aims at. Two rows rather than a free-text
/// FormID field, for the reason `ActorValueTargetSelector` has two: the
/// question a session asks is "this one in front of me" or "whoever is
/// closest", and a typed FormID is a third thing that can be wrong.
nonisolated public enum DialogueCameraTarget: String, CaseIterable, Equatable, Sendable {
    /// The actor the crosshair is on, which is the one a conversation would
    /// open with.
    case crosshair
    /// The nearest resident actor, so the toggle still has a subject when the
    /// crosshair is on a wall.
    case nearestActor

    public var label: String {
        switch self {
        case .crosshair: "Crosshair target"
        case .nearestActor: "Nearest actor"
        }
    }
}
