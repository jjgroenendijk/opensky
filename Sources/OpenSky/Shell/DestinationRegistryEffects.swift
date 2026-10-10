// The effects destination, split out of DestinationRegistry.swift to stay
// under the type-length cap. A forced image space, a disabled pass, and
// effects attached from the panel are overrides; explosions are world events.

import AppKit
import OpenSkyCombat
import OpenSkyWorld

extension DestinationRegistry {
    static let effectsDestinations: [DestinationDescriptor] = [
        DestinationDescriptor(
            id: "effects",
            title: "Effects",
            section: .world,
            symbolName: "sparkles",
            content: .worldInspector { context in
                let panel = EffectsPanelViewController()
                panel.imageSpaceProvider = context.providers
                panel.visualEffectProvider = context.providers
                panel.impactProvider = context.providers
                panel.explosionProvider = context.providers
                let providers = context.providers
                panel.refocusAction = { [weak providers] in providers?.refocusGameView() }
                return panel
            },
            overrides: DestinationOverrideActions(
                isOverridden: { context in
                    ImageSpaceSection.isOverridden(provider: context.providers)
                        || VisualEffectSection.isOverridden(provider: context.providers)
                        || ImpactSection.isOverridden(provider: context.providers)
                },
                resetToDefaults: { context in
                    ImageSpaceSection.resetToDefaults(provider: context.providers)
                    VisualEffectSection.resetToDefaults(provider: context.providers)
                    ImpactSection.resetToDefaults(provider: context.providers)
                }
            )
        )
    ]
}
