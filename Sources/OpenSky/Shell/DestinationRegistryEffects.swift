// The effects destination, split out of DestinationRegistry.swift to stay
// under the type-length cap. A forced image space, a disabled pass, and
// effects attached from the panel are overrides; explosions are world events.

import AppKit
import OpenSkyCombat

extension DestinationRegistry {
    static let effectsDestinations: [DestinationDescriptor] = [
        DestinationDescriptor(
            id: "effects",
            title: "Effects",
            section: .world,
            symbolName: "sparkles",
            content: .worldInspector { context in
                let panel = EffectsPanelViewController()
                panel.imageSpaceProvider = context.imageSpace
                panel.visualEffectProvider = context.visualEffect
                panel.impactProvider = context.impact
                panel.explosionProvider = context.explosion
                return panel
            },
            overrides: DestinationOverrideActions(
                isOverridden: { context in
                    ImageSpaceSection.isOverridden(provider: context.imageSpace)
                        || VisualEffectSection.isOverridden(provider: context.visualEffect)
                        || ImpactSection.isOverridden(provider: context.impact)
                },
                resetToDefaults: { context in
                    ImageSpaceSection.resetToDefaults(provider: context.imageSpace)
                    VisualEffectSection.resetToDefaults(provider: context.visualEffect)
                    ImpactSection.resetToDefaults(provider: context.impact)
                }
            )
        )
    ]
}
