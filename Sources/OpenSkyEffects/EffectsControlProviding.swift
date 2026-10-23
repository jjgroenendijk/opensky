// Snapshots of image-space pass and the visual effects.

import OpenSkyGameData
import OpenSkyRendering

nonisolated public struct VisualEffectSnapshot: Equatable, Sendable {
    public let instances: [VisualEffectInstance]
    public let attachedTotal: Int
    public let failedModels: Int
    public let lastSpellHit: String

    public init(
        instances: [VisualEffectInstance], attachedTotal: Int, failedModels: Int,
        lastSpellHit: String
    ) {
        self.instances = instances
        self.attachedTotal = attachedTotal
        self.failedModels = failedModels
        self.lastSpellHit = lastSpellHit
    }
}
