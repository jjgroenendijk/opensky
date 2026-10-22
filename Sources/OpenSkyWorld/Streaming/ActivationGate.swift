// The check every use-key activation passes before it publishes. The lock runtime
// answers it; a refused press raises a refusal event and nothing else.
// See docs/engine/locks.md.

import OpenSkyPlayer
import OpenSkyWorldInterface

@MainActor
public struct ActivationGateSeam {
    /// Asked once per press. Nil, or a nil answer, lets the activation through.
    public var gate: ((InteractionTarget) -> ActivationRefusal?)?
    /// Asked after the gate lets a press through. True means the player's perk
    /// choices took the press over, so the target's own action does not run.
    public var perkChoices: ((InteractionTarget) -> Bool)?
    /// Fires for each refused press. The HUD, audio, and the lockpicking menu listen.
    public let refusals = CallbackFanOut<ActivationRefusalEvent>()
}
