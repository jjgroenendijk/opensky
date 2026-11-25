// The running image space modifiers as `state` reads and the frame readout show them.

import OpenSkyAgentControl
import OpenSkyRenderCore

extension ImageSpaceModifierRuntime {
    /// Each running modifier, its strength now, and how long it has run.
    var agentJSON: AgentJSON {
        .array(instances.map { instance in
            [
                "name": .string(instance.name), "strength": .init(instance.strength),
                "currentStrength": .init(instance.currentStrength),
                "elapsed": .init(instance.elapsed), "held": .bool(instance.looping),
                "fadeIn": .init(instance.fadeIn),
                "remaining": instance.remaining.map { .init($0) } ?? .null
            ]
        })
    }
}
