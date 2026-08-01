// The three menu destinations' override actions (issue #179 split them out).
// Satellite of Shell/DestinationRegistry.swift, which holds the descriptors:
// the registry enum body is at the strict-lint type-length cap, and these three
// constants are the part of it that is pure per-destination policy.
//
// `fileprivate` rather than `private` because they are consumed from the
// descriptor list in the main file; the registry stays the only registration
// point either way.

import AppKit

extension DestinationRegistry {
    static let systemMenuOverrides = DestinationOverrideActions(
        isOverridden: { context in
            SystemMenuSection.isOverridden(provider: context.providers)
                || SystemMenuSettingsSection.isOverridden(provider: context.providers)
        },
        resetToDefaults: { context in
            SystemMenuSection.resetToDefaults(provider: context.providers)
            SystemMenuSettingsSection.resetToDefaults(provider: context.providers)
        }
    )

    static let inventoryMenuOverrides = DestinationOverrideActions(
        isOverridden: { context in
            InventoryMenuSection.isOverridden(provider: context.providers)
        },
        resetToDefaults: { context in
            InventoryMenuSection.resetToDefaults(provider: context.providers)
        }
    )

    /// Only the Menu section carries overridden-ness: the Merchant section
    /// nominates a target rather than setting a value, and closing the menu
    /// leaves that nomination alone so reopening lands on the same chest.
    static let containerMenuOverrides = DestinationOverrideActions(
        isOverridden: { context in
            ContainerMenuSection.isOverridden(provider: context.providers)
        },
        resetToDefaults: { context in
            ContainerMenuSection.resetToDefaults(provider: context.providers)
        }
    )
}
