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
    static let audioOverrides = DestinationOverrideActions(
        isOverridden: { context in
            AudioOutputSection.isOverridden(provider: context.providers)
                || AudioSfxSection.isOverridden(provider: context.providers)
                || AudioMusicSection.isOverridden(provider: context.providers)
                || AudioFootstepsSection.isOverridden(provider: context.providers)
        },
        resetToDefaults: { context in
            AudioOutputSection.resetToDefaults(provider: context.providers)
            AudioSfxSection.resetToDefaults(provider: context.providers)
            AudioMusicSection.resetToDefaults(provider: context.providers)
            AudioFootstepsSection.resetToDefaults(provider: context.providers)
        }
    )

    /// Only the HUD elements section carries overridden-ness now that the
    /// conversation moved to its own destination (issue #209): what the
    /// crosshair is pointing at and what a picked item did are world state, and
    /// the presentation toggles above them are the settings a reset restores.
    static let hudInteractionOverrides = DestinationOverrideActions(
        isOverridden: { context in
            HUDElementsSection.isOverridden(provider: context.providers)
        },
        resetToDefaults: { context in
            HUDElementsSection.resetToDefaults(provider: context.providers)
        }
    )

    /// The M17 destination's four sections all carry overridden-ness, and each
    /// for the same reason: every one of them can be left holding something the
    /// world would not have produced on its own. An open conversation holds the
    /// engine menu stack, a forced dialogue camera holds the view, a scrubbed
    /// morph weight holds a face, and lip sync switched off is the A/B seam left
    /// in its non-default half. Said-state and quest stages a conversation
    /// produced are deliberately not undone: those are the milestone's point.
    static let dialogueVoiceOverrides = DestinationOverrideActions(
        isOverridden: { context in
            DialogueSection.isOverridden(provider: context.providers)
                || DialogueCameraSection.isOverridden(provider: context.providers)
                || AudioVoiceSection.isOverridden(provider: context.providers)
                || FaceMorphSection.isOverridden(provider: context.providers)
        },
        resetToDefaults: { context in
            DialogueSection.resetToDefaults(provider: context.providers)
            DialogueCameraSection.resetToDefaults(provider: context.providers)
            AudioVoiceSection.resetToDefaults(provider: context.providers)
            FaceMorphSection.resetToDefaults(provider: context.providers)
        }
    )

    /// The launch destination's settable sections: the camera mode, the
    /// first-person controls beside it, and the render-debug view filters. A
    /// wireframe or a hidden layer left on is the case the sidebar dot exists
    /// for — it reads as a rendering bug from anywhere else in the app.
    static let worldOverrides = DestinationOverrideActions(
        isOverridden: {
            CameraSection.isOverridden(provider: $0.providers)
                || FirstPersonSection.isOverridden(provider: $0.providers)
                || RenderDebugSection.isOverridden(provider: $0.providers)
        },
        resetToDefaults: {
            CameraSection.resetToDefaults(provider: $0.providers)
            FirstPersonSection.resetToDefaults(provider: $0.providers)
            RenderDebugSection.resetToDefaults(provider: $0.providers)
        }
    )

    /// Only the Dev Controls section carries overridden-ness (issue #191): a
    /// held gait is the one thing under `World > Player & Locomotion` that sits
    /// away from its default, and the sidebar's reset releases it. Camera mode
    /// is `World > World`'s override and is deliberately not claimed twice;
    /// sneaking, jumping and raising an event are world actions rather than
    /// settings, so none of them lights the dot.
    static let playerLocomotionOverrides = DestinationOverrideActions(
        isOverridden: { context in
            LocomotionDevSection.isOverridden(provider: context.providers)
        },
        resetToDefaults: { context in
            LocomotionDevSection.resetToDefaults(provider: context.providers)
        }
    )

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

    /// Only the Physics section carries overridden-ness: a frozen simulation is
    /// the one thing under this destination that sits away from its default,
    /// and the sidebar's reset resumes it. A damaged actor, an angry opponent,
    /// a corpse on the floor and a shoved crate are all world state a user made
    /// on purpose, and a "Reset all" that undid any of them would be undoing
    /// the fight rather than a setting.
    static let combatPhysicsOverrides = DestinationOverrideActions(
        isOverridden: { context in
            CombatPhysicsSection.isOverridden(provider: context.providers)
        },
        resetToDefaults: { context in
            CombatPhysicsSection.resetToDefaults(provider: context.providers)
        }
    )

    /// Only the Overlays section carries overridden-ness (issue #203): three
    /// debug overlays that default off are the one thing under this destination
    /// that sits away from a documented default, and the sidebar's reset
    /// switches them back off. Which actor a session is following is a
    /// nomination rather than a setting; where an actor has walked to, which
    /// package its clock selected and whether it regards the player as an enemy
    /// are all world state a user produced on purpose, and a "Reset all" that
    /// undid any of them would be undoing the demonstration rather than a knob.
    static let aiNavigationOverrides = DestinationOverrideActions(
        isOverridden: { context in
            AIOverlaySection.isOverridden(provider: context.providers)
        },
        resetToDefaults: { context in
            AIOverlaySection.resetToDefaults(provider: context.providers)
        }
    )

    /// Only the Reset section carries overridden-ness: a dirty reference is the
    /// world deviating from plugin data, which is this destination's notion of
    /// a non-default value, and "Reset all" is what restores it. Inspecting and
    /// saving change no setting.
    static let runtimeStateOverrides = DestinationOverrideActions(
        isOverridden: { context in
            RuntimeStateResetSection.isOverridden(provider: context.providers)
        },
        resetToDefaults: { context in
            RuntimeStateResetSection.resetToDefaults(provider: context.providers)
        }
    )

    /// Only the Scheduler section carries overridden-ness: a paused Papyrus VM
    /// is the one thing under this destination that sits away from its default,
    /// and the sidebar's reset resumes it. Stepping leaves no setting behind,
    /// and the other three sections are read-only.
    static let scriptsOverrides = DestinationOverrideActions(
        isOverridden: { context in
            ScriptSchedulerSection.isOverridden(provider: context.providers)
        },
        resetToDefaults: { context in
            ScriptSchedulerSection.resetToDefaults(provider: context.providers)
        }
    )

    static let uiLabOverrides = DestinationOverrideActions(
        isOverridden: { context in
            UILabControlsSection.isOverridden(provider: context.providers)
                || SWFMovieSection.isOverridden(provider: context.providers)
        },
        resetToDefaults: { context in
            UILabControlsSection.resetToDefaults(provider: context.providers)
            SWFMovieSection.resetToDefaults(provider: context.providers)
        }
    )
}
