// Per-destination override actions, split out of DestinationRegistry.swift to
// stay under the type-length cap. `fileprivate` because the descriptor list in
// the main file uses them.

import AppKit
import OpenSkyMenus

extension DestinationRegistry {
    static let audioOverrides = DestinationOverrideActions(
        isOverridden: { context in
            AudioOutputSection.isOverridden(provider: context.audio)
                || AudioSfxSection.isOverridden(provider: context.audio)
                || AudioMusicSection.isOverridden(provider: context.audio)
                || AudioFootstepsSection.isOverridden(provider: context.audio)
                || AudioReverbSection.isOverridden(provider: context.audio)
        },
        resetToDefaults: { context in
            AudioOutputSection.resetToDefaults(provider: context.audio)
            AudioSfxSection.resetToDefaults(provider: context.audio)
            AudioMusicSection.resetToDefaults(provider: context.audio)
            AudioFootstepsSection.resetToDefaults(provider: context.audio)
            AudioReverbSection.resetToDefaults(provider: context.audio)
        }
    )

    /// Only the HUD elements section is overridable. The crosshair target and
    /// picked items are world state.
    static let hudInteractionOverrides = DestinationOverrideActions(
        isOverridden: { context in
            HUDElementsSection.isOverridden(provider: context.hud)
        },
        resetToDefaults: { context in
            HUDElementsSection.resetToDefaults(provider: context.hud)
        }
    )

    /// Every section here can hold something the world would not produce: an
    /// open conversation, a forced camera, a scrubbed morph, lip sync off.
    /// Said-state and quest stages from a conversation are not undone.
    static let dialogueVoiceOverrides = DestinationOverrideActions(
        isOverridden: { context in
            DialogueSection.isOverridden(provider: context.dialogue)
                || DialogueCameraSection.isOverridden(provider: context.dialogueCamera)
                || AudioVoiceSection.isOverridden(provider: context.audio)
                || FaceMorphSection.isOverridden(provider: context.faceMorph)
        },
        resetToDefaults: { context in
            DialogueSection.resetToDefaults(provider: context.dialogue)
            DialogueCameraSection.resetToDefaults(provider: context.dialogueCamera)
            AudioVoiceSection.resetToDefaults(provider: context.audio)
            FaceMorphSection.resetToDefaults(provider: context.faceMorph)
        }
    )

    /// The launch destination's settable sections: the camera mode, the
    /// first-person controls beside it, and the render-debug view filters. A
    /// wireframe or a hidden layer left on is the case the sidebar dot exists
    /// for — it reads as a rendering bug from anywhere else in the app.
    static let worldOverrides = DestinationOverrideActions(
        isOverridden: {
            CameraSection.isOverridden(provider: $0.camera)
                || FirstPersonSection.isOverridden(provider: $0.firstPerson)
                || RenderDebugSection.isOverridden(provider: $0.renderDebug)
        },
        resetToDefaults: {
            CameraSection.resetToDefaults(provider: $0.camera)
            FirstPersonSection.resetToDefaults(provider: $0.firstPerson)
            RenderDebugSection.resetToDefaults(provider: $0.renderDebug)
        }
    )

    /// Only a held gait is overridable. Camera mode belongs to `World > World`;
    /// sneak, jump, and raised events are world actions, not settings.
    static let playerLocomotionOverrides = DestinationOverrideActions(
        isOverridden: { context in
            LocomotionDevSection.isOverridden(provider: context.playerLocomotion)
        },
        resetToDefaults: { context in
            LocomotionDevSection.resetToDefaults(provider: context.playerLocomotion)
        }
    )

    static let playerSettingsOverrides = DestinationOverrideActions(
        isOverridden: { KeyBindingsSection.isOverridden(provider: $0.playerSettings) },
        resetToDefaults: { KeyBindingsSection.resetToDefaults(provider: $0.playerSettings) }
    )

    static let systemMenuOverrides = DestinationOverrideActions(
        isOverridden: { context in
            SystemMenuSection.isOverridden(provider: context.systemMenu)
                || SystemMenuSettingsSection.isOverridden(provider: context.systemMenu)
        },
        resetToDefaults: { context in
            SystemMenuSection.resetToDefaults(provider: context.systemMenu)
            SystemMenuSettingsSection.resetToDefaults(provider: context.systemMenu)
        }
    )

    /// An open title or race menu holds the world paused.
    static let characterMenuOverrides = DestinationOverrideActions(
        isOverridden: { context in
            context.titleMenu.titleMenuSnapshot.isOpen || context.raceMenu.raceMenuSnapshot.isOpen
                || context.skillsMenu.skillsMenuSnapshot.isOpen
        },
        resetToDefaults: { context in
            if context.skillsMenu.skillsMenuSnapshot.isOpen {
                context.skillsMenu.sendSkillsMenuInput(.button(.cancel))
            }
            if context.raceMenu.raceMenuSnapshot.isOpen {
                context.raceMenu.sendRaceMenuInput(.button(.cancel))
            }
            context.titleMenu.closeTitleMenu()
        }
    )

    static let mapMenuOverrides = DestinationOverrideActions(
        isOverridden: { context in context.mapMenu.mapMenuSnapshot.mode != nil },
        resetToDefaults: { context in context.mapMenu.closeMap() }
    )

    static let inventoryMenuOverrides = DestinationOverrideActions(
        isOverridden: { context in
            InventoryMenuSection.isOverridden(provider: context.inventoryMenu)
        },
        resetToDefaults: { context in
            InventoryMenuSection.resetToDefaults(provider: context.inventoryMenu)
        }
    )

    /// Only the Equipment owner selector is overridable. A grant is a world
    /// change, and `World > Runtime State` already owns resetting it.
    static let inventoryEquipmentOverrides = DestinationOverrideActions(
        isOverridden: { context in
            EquipmentInspectionSection.isOverridden(provider: context.inventoryEquipment)
        },
        resetToDefaults: { context in
            EquipmentInspectionSection.resetToDefaults(provider: context.inventoryEquipment)
        }
    )

    /// Only the Menu section carries overridden-ness: the Merchant section
    /// nominates a target rather than setting a value, and closing the menu
    /// leaves that nomination alone so reopening lands on the same chest.
    static let containerMenuOverrides = DestinationOverrideActions(
        isOverridden: { context in
            ContainerMenuSection.isOverridden(provider: context.containerMenu)
        },
        resetToDefaults: { context in
            ContainerMenuSection.resetToDefaults(provider: context.containerMenu)
        }
    )

    /// Only the Page section carries overridden-ness: an open journal sits on
    /// the menu stack and pauses world simulation, and the sidebar's reset
    /// closes it. Starting or advancing a quest is world state rather than a
    /// panel setting, so "Reset all" deliberately leaves it alone.
    static let journalOverrides = DestinationOverrideActions(
        isOverridden: { context in
            JournalPageSection.isOverridden(provider: context.journal)
        },
        resetToDefaults: { context in
            JournalPageSection.resetToDefaults(provider: context.journal)
        }
    )

    static let environmentOverrides = DestinationOverrideActions(
        isOverridden: { context in
            ShadowSection.isOverridden(provider: context.shadow)
                || AnimationSection.isOverridden(provider: context.animation)
                || WeatherSection.isOverridden(provider: context.weather)
                || ParticlesSection.isOverridden(provider: context.particle)
                || PrecipitationSection.isOverridden(provider: context.precipitation)
                || WaterSection.isOverridden(provider: context.water)
                || TerrainSection.isOverridden(provider: context.terrainShading)
                || SurfaceShadingSection.isOverridden(provider: context.surfaceShading)
                || GrassSection.isOverridden(provider: context.grass)
                || TerrainLODSection.isOverridden(provider: context.terrainLOD)
        },
        resetToDefaults: { context in
            ShadowSection.resetToDefaults(provider: context.shadow)
            AnimationSection.resetToDefaults(provider: context.animation)
            WeatherSection.resetToDefaults(provider: context.weather)
            ParticlesSection.resetToDefaults(provider: context.particle)
            PrecipitationSection.resetToDefaults(provider: context.precipitation)
            WaterSection.resetToDefaults(provider: context.water)
            TerrainSection.resetToDefaults(provider: context.terrainShading)
            SurfaceShadingSection.resetToDefaults(provider: context.surfaceShading)
            GrassSection.resetToDefaults(provider: context.grass)
            TerrainLODSection.resetToDefaults(provider: context.terrainLOD)
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
            CombatPhysicsSection.isOverridden(provider: context.physics)
        },
        resetToDefaults: { context in
            CombatPhysicsSection.resetToDefaults(provider: context.physics)
        }
    )

    /// Only the debug overlays are overridable. The followed actor, its
    /// position, its package, and its hostility are world state the user made
    /// on purpose.
    static let aiNavigationOverrides = DestinationOverrideActions(
        isOverridden: { context in
            AIOverlaySection.isOverridden(provider: context.aiOverlay)
                || AIIdleSection.isOverridden(provider: context.idle)
                || AIBehaviorGraphSection.isOverridden(provider: context.actorGraph)
        },
        resetToDefaults: { context in
            AIOverlaySection.resetToDefaults(provider: context.aiOverlay)
            AIIdleSection.resetToDefaults(provider: context.idle)
            AIBehaviorGraphSection.resetToDefaults(provider: context.actorGraph)
        }
    )

    /// Only the Reset section carries overridden-ness: a dirty reference is the
    /// world deviating from plugin data, which is this destination's notion of
    /// a non-default value, and "Reset all" is what restores it. Inspecting and
    /// saving change no setting.
    static let runtimeStateOverrides = DestinationOverrideActions(
        isOverridden: { context in
            RuntimeStateResetSection.isOverridden(provider: context.runtimeState)
        },
        resetToDefaults: { context in
            RuntimeStateResetSection.resetToDefaults(provider: context.runtimeState)
        }
    )

    /// Only the Scheduler section carries overridden-ness: a paused Papyrus VM
    /// is the one thing under this destination that sits away from its default,
    /// and the sidebar's reset resumes it. Stepping leaves no setting behind,
    /// and the other three sections are read-only.
    static let scriptsOverrides = DestinationOverrideActions(
        isOverridden: { context in
            ScriptSchedulerSection.isOverridden(provider: context.script)
        },
        resetToDefaults: { context in
            ScriptSchedulerSection.resetToDefaults(provider: context.script)
        }
    )

    static let uiLabOverrides = DestinationOverrideActions(
        isOverridden: { context in
            UILabControlsSection.isOverridden(provider: context.uiLab)
                || SWFMovieSection.isOverridden(provider: context.swfLab)
        },
        resetToDefaults: { context in
            UILabControlsSection.resetToDefaults(provider: context.uiLab)
            SWFMovieSection.resetToDefaults(provider: context.swfLab)
        }
    )

    static let renderingPerformanceOverrides = DestinationOverrideActions(
        isOverridden: { context in
            PipelineCacheSection.isOverridden(provider: context.renderPerformance)
                || GPUCullingSection.isOverridden(provider: context.renderPerformance)
                || RoomCullingSection.isOverridden(provider: context.renderPerformance)
                || TextureStreamingSection.isOverridden(provider: context.renderPerformance)
                || RayTracedShadowsSection.isOverridden(provider: context.renderPerformance)
                || UpscalingSection.isOverridden(provider: context.renderPerformance)
                || FrameInterpolationSection.isOverridden(provider: context.renderPerformance)
                || MeshShaderGrassSection.isOverridden(provider: context.renderPerformance)
        },
        resetToDefaults: { context in
            PipelineCacheSection.resetToDefaults(provider: context.renderPerformance)
            GPUCullingSection.resetToDefaults(provider: context.renderPerformance)
            RoomCullingSection.resetToDefaults(provider: context.renderPerformance)
            TextureStreamingSection.resetToDefaults(provider: context.renderPerformance)
            RayTracedShadowsSection.resetToDefaults(provider: context.renderPerformance)
            UpscalingSection.resetToDefaults(provider: context.renderPerformance)
            FrameInterpolationSection.resetToDefaults(provider: context.renderPerformance)
            MeshShaderGrassSection.resetToDefaults(provider: context.renderPerformance)
        }
    )
}
