// Snapshots of image-space pass and the visual effects.

import OpenSkyGameData
public import OpenSkyRendering

nonisolated struct VisualEffectSnapshot: Equatable, Sendable {
    let instances: [VisualEffectInstance]
    let attachedTotal: Int
    let failedModels: Int
    let lastSpellHit: String
}
