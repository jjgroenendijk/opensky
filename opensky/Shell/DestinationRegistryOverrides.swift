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

    /// Only the Equipment section carries overridden-ness, and only through its
    /// owner selector (issue #180). Granting, and the ownership readout, change
    /// no setting: a grant is a world change, which `World > Runtime State`
    /// already owns resetting, and giving the same delta two owners is exactly
    /// what the reset contract forbids. Inspecting the player instead of the
    /// nearest NPC is the one thing here that sits away from a documented
    /// default, and the sidebar's reset puts it back.
    static let inventoryEquipmentOverrides = DestinationOverrideActions(
        isOverridden: { context in
            EquipmentInspectionSection.isOverridden(provider: context.providers)
        },
        resetToDefaults: { context in
            EquipmentInspectionSection.resetToDefaults(provider: context.providers)
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

    /// Only the Page section carries overridden-ness: an open journal sits on
    /// the menu stack and pauses world simulation, and the sidebar's reset
    /// closes it. Starting or advancing a quest is world state rather than a
    /// panel setting, so "Reset all" deliberately leaves it alone.
    static let journalOverrides = DestinationOverrideActions(
        isOverridden: { context in
            JournalPageSection.isOverridden(provider: context.providers)
        },
        resetToDefaults: { context in
            JournalPageSection.resetToDefaults(provider: context.providers)
        }
    )

    static let environmentOverrides = DestinationOverrideActions(
        isOverridden: { context in
            let providers = context.providers
            return ShadowSection.isOverridden(provider: providers)
                || AnimationSection.isOverridden(provider: providers)
                || WeatherSection.isOverridden(provider: providers)
                || ParticlesSection.isOverridden(provider: providers)
                || PrecipitationSection.isOverridden(provider: providers)
                || GrassSection.isOverridden(provider: providers)
                || TerrainLODSection.isOverridden(provider: providers)
        },
        resetToDefaults: { context in
            let providers = context.providers
            ShadowSection.resetToDefaults(provider: providers)
            AnimationSection.resetToDefaults(provider: providers)
            WeatherSection.resetToDefaults(provider: providers)
            ParticlesSection.resetToDefaults(provider: providers)
            PrecipitationSection.resetToDefaults(provider: providers)
            GrassSection.resetToDefaults(provider: providers)
            TerrainLODSection.resetToDefaults(provider: providers)
        }
    )
}
