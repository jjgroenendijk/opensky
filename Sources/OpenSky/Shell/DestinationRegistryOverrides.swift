// Per-destination override actions, split out of DestinationRegistry.swift to
// stay under the type-length cap. `fileprivate` because the descriptor list in
// the main file uses them.

import AppKit
import OpenSkyMenus

extension DestinationRegistry {
    static let audioOverrides = DestinationOverrideActions(
        isOverridden: { context in
            AudioOutputSection.isOverridden(provider: context.providers)
                || AudioSfxSection.isOverridden(provider: context.providers)
                || AudioMusicSection.isOverridden(provider: context.providers)
                || AudioFootstepsSection.isOverridden(provider: context.providers)
                || AudioReverbSection.isOverridden(provider: context.providers)
        },
        resetToDefaults: { context in
            AudioOutputSection.resetToDefaults(provider: context.providers)
            AudioSfxSection.resetToDefaults(provider: context.providers)
            AudioMusicSection.resetToDefaults(provider: context.providers)
            AudioFootstepsSection.resetToDefaults(provider: context.providers)
            AudioReverbSection.resetToDefaults(provider: context.providers)
        }
    )

    /// Only the HUD elements section is overridable. The crosshair target and
    /// picked items are world state.
    static let hudInteractionOverrides = DestinationOverrideActions(
        isOverridden: { context in
            HUDElementsSection.isOverridden(provider: context.providers)
        },
        resetToDefaults: { context in
            HUDElementsSection.resetToDefaults(provider: context.providers)
        }
    )

    /// Every section here can hold something the world would not produce: an
    /// open conversation, a forced camera, a scrubbed morph, lip sync off.
    /// Said-state and quest stages from a conversation are not undone.
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

    /// Only a held gait is overridable. Camera mode belongs to `World > World`;
    /// sneak, jump, and raised events are world actions, not settings.
    static let playerLocomotionOverrides = DestinationOverrideActions(
        isOverridden: { context in
            LocomotionDevSection.isOverridden(provider: context.providers)
        },
        resetToDefaults: { context in
            LocomotionDevSection.resetToDefaults(provider: context.providers)
        }
    )

    static let playerSettingsOverrides = DestinationOverrideActions(
        isOverridden: { KeyBindingsSection.isOverridden(provider: $0.providers) },
        resetToDefaults: { KeyBindingsSection.resetToDefaults(provider: $0.providers) }
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

    /// An open title or race menu holds the world paused.
    static let characterMenuOverrides = DestinationOverrideActions(
        isOverridden: { context in
            context.providers.titleMenuSnapshot.isOpen || context.providers.raceMenuSnapshot.isOpen
        },
        resetToDefaults: { context in
            if context.providers.raceMenuSnapshot.isOpen {
                context.providers.sendRaceMenuInput(.button(.cancel))
            }
            context.providers.closeTitleMenu()
        }
    )

    static let mapMenuOverrides = DestinationOverrideActions(
        isOverridden: { context in context.providers.mapMenuSnapshot.mode != nil },
        resetToDefaults: { context in context.providers.closeMap() }
    )

    static let inventoryMenuOverrides = DestinationOverrideActions(
        isOverridden: { context in
            InventoryMenuSection.isOverridden(provider: context.providers)
        },
        resetToDefaults: { context in
            InventoryMenuSection.resetToDefaults(provider: context.providers)
        }
    )

    /// Only the Equipment owner selector is overridable. A grant is a world
    /// change, and `World > Runtime State` already owns resetting it.
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

    /// Only the debug overlays are overridable. The followed actor, its
    /// position, its package, and its hostility are world state the user made
    /// on purpose.
    static let aiNavigationOverrides = DestinationOverrideActions(
        isOverridden: { context in
            AIOverlaySection.isOverridden(provider: context.providers)
                || AIIdleSection.isOverridden(provider: context.providers)
        },
        resetToDefaults: { context in
            AIOverlaySection.resetToDefaults(provider: context.providers)
            AIIdleSection.resetToDefaults(provider: context.providers)
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

    static let renderingPerformanceOverrides = DestinationOverrideActions(
        isOverridden: { context in
            PipelineCacheSection.isOverridden(provider: context.providers)
                || GPUCullingSection.isOverridden(provider: context.providers)
                || TextureStreamingSection.isOverridden(provider: context.providers)
        },
        resetToDefaults: { context in
            PipelineCacheSection.resetToDefaults(provider: context.providers)
            GPUCullingSection.resetToDefaults(provider: context.providers)
            TextureStreamingSection.resetToDefaults(provider: context.providers)
        }
    )
}
