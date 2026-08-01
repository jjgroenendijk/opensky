---
type: Convention
title: Sidebar verification convention + acceptance ledger
description: The record every milestone acceptance must produce — sidebar path, destination
  and control accessibility ids, readout, and the deterministic tests that are the evidence —
  plus the per-milestone ledger of what was actually recorded.
tags: [app-ui, verification, acceptance, convention]
timestamp: 2026-08-01T00:00:00Z
---

# Sidebar verification convention

Every milestone ships a durable main-app surface (AGENTS.md "Main-app verification
surface"). This page defines what that milestone must write down at acceptance, where the
record goes, and what counts as evidence. The framework and placement rules — how to
register a destination and build a panel — live in
[Main-app UI framework](/tools/app-ui.md). That page is the prerequisite; this page does not
link back into it, so the two read in one direction.

## Contents

- What is mandatory
- The record format
- Where the record goes
- Acceptance ledger — one row per milestone that recorded a surface

## What is mandatory

The record is mandatory. Screenshots are not.

The deterministic test suite is the acceptance evidence: the panel geometry and
accessibility-id assertions (`EnvironmentPanelTests`, `UILabPanelTests`,
`HUDInteractionPanelTests`, `SystemMenuPanelTests`, `AudioPanelTests`, `WorldPanelTests`,
`PanelFrameworkTests`), the destination contract in `DestinationRegistryTests`, and any
offscreen render acceptance test the milestone already has. If those pass, the acceptance
gate is satisfied. No milestone needs to produce a changed-pixel A/B capture to be
accepted.

An A/B capture stays useful for a human sanity check, so it remains allowed — but it is
optional, local-only, and never committed. Captures go to `logs/`, which is gitignored.
A frame OpenSky renders from a real install embeds Bethesda textures, meshes, and UI art,
so committing one would redistribute game content; see AGENTS.md "Legal & IP boundary".
Link the local path from a pull request if it helps a reviewer; do not add the file.

## The record format

Each milestone acceptance produces one record in this fixed shape:

```text
Milestone: M8.4.3
Sidebar path: World > HUD & Interaction > Elements
Destination id: Destination-hudInteraction
Controls exercised: HUDLayerEnabledControl, HUDCrosshairControl, HUDScaleControl
Readout: HUDElementsStatsLabel
Deterministic tests: HUDInteractionPanelTests, DestinationRegistryTests
Local A/B (optional, never committed): logs/hud-elements-ab.png
```

Field rules:

- **Sidebar path** — the literal breadcrumb a user clicks, sections included, exactly as
  the sidebar and section headers spell it (`World > Environment > Weather`).
- **Destination id** — the accessibility id of the sidebar row, always
  `Destination-<id>` for one of the ids registered in `DestinationRegistry`.
- **Controls exercised** — the literal accessibility ids of the controls the acceptance
  actually touched, not every control on the panel. Ids that are generated at runtime
  rather than written as literals (the `Audio<Category>VolumeControl`,
  `Audio<Category>MuteControl` and `Audio<Category>SoloControl` families, all built in
  `AudioOutputSection.swift`) must be named as a family with that caveat, because they
  cannot be found by grepping for the full id.
- **Readout** — the accessibility id of the label whose text proves the behavior changed.
  A record with no readout is incomplete: without it there is nothing for a later session
  to re-check.
- **Deterministic tests** — the test classes that pin the above. These are the evidence.
- **Local A/B** — optional. A path under `logs/` or the word `none`.

## Where the record goes

Two places, in the same commit as the work:

1. The subsystem's own wiki page, in its verification section, where the ids are
   explained in context.
2. The [ledger](#acceptance-ledger) below, as one row, so a later session can find every
   recorded path in one place without grepping.

The `docs/log.md` entry for the milestone may repeat the path in prose; the ledger is the
authoritative index.

## Acceptance ledger

One row per milestone or sub-milestone that recorded a surface. "Not recorded" means no
existing doc states it — the row is not an invitation to reconstruct one from memory.

Issue #170 explicitly defines M11.1 as headless and assigns the discoverable
`World > Scripts` surface to M11.2. Its row records that authored exception
instead of inventing accessibility ids. `PapyrusTallySnapshot` is the durable
headless readout for this sub-milestone; the normal UI-shaped record becomes
mandatory again at M11.2.

The UI-test column is deliberately absent: the id contract is pinned in unit tests instead,
because the UI-test harness does not run on every machine
([local environment](/tools/environment.md)).

| Milestone | Sidebar path | Destination id | Controls exercised | Readout | Deterministic tests | Recorded in |
|---|---|---|---|---|---|---|
| M1-M6 | Not recorded | — | — | — | — | Convention postdates them (2026-07-21) |
| M3.3 | `Library > Asset Browser` | `Destination-assetBrowser` | Not recorded | Not recorded | `DestinationRegistryTests` | [asset browser](/tools/preview-gui.md) |
| M3 distant LOD | `World > Environment > Distant LOD` | `Destination-environment` | `LODLevel0DistanceControl`, `LODLevel1DistanceControl`, `LODMaximumDistanceControl`, `LODTreeDistanceControl`, `LODApplyControl`, `LODResetControl` | `LODStatsLabel` | `EnvironmentPanelTests` | [distant LOD](/engine/distant-lod.md) |
| M4 movement tuning | `World > World > Camera` | `Destination-world` | `CameraMovementModeControl` | `CameraStatsLabel` | `WorldPanelTests`, `WalkControllerTests`, `WalkControllerConfigurationTests`, `GameSettingStoreTests` | [terrain walk mode](/engine/walk-mode.md) |
| M7.1 sun shadows | `World > Environment > Sun shadows` | `Destination-environment` | `SunShadowsEnabledControl`, `ShadowQualityControl` | `ShadowStatsLabel` | `EnvironmentPanelTests` | [shadows](/rendering/shadows.md) |
| M7 actor animation | `World > Environment > Actor animation` | `Destination-environment` | `AnimationsEnabledControl` | `AnimationStatsLabel` | `EnvironmentPanelTests` | [actor animation](/engine/actor-animation.md) |
| M7.2 weather | `World > Environment > Weather` | `Destination-environment` | `WeatherEnabledControl`, `WeatherControl`, `ClearWeatherControl`, `RainWeatherControl`, `SnowWeatherControl`, `WeatherTransitionsPausedControl`, `TimeOfDayControl` | `WeatherStatsLabel`, `TimeOfDayStatsLabel` | `EnvironmentPanelTests`, `WeatherAcceptanceRealDataTests` | [weather](/engine/weather.md) |
| M7.3 particles | `World > Environment > Particles` | `Destination-environment` | `ParticlesEnabledControl`, `ParticlesFrozenControl`, `ParticleEmissionControl` | `ParticleStatsLabel` | `EnvironmentPanelTests` | [particles](/rendering/particles.md) |
| M7.4 precipitation | `World > Environment` | `Destination-environment` | `PrecipitationEnabledControl` | `PrecipitationStatsLabel` | `EnvironmentPanelTests`, `PrecipitationAcceptanceRealDataTests` | [precipitation](/rendering/precipitation.md) |
| M7.5.2 grass | `World > Environment > Grass` | `Destination-environment` | `GrassEnabledControl`, `GrassDensityControl`, `GrassDistanceControl`, `GrassWindControl` | `GrassStatsLabel` | `EnvironmentPanelTests`, `GrassRenderingAcceptanceRealDataTests` | [grass](/engine/grass.md) |
| M7.6 living environment | `World > Environment` | `Destination-environment` | Every enable toggle above | Every stats label above | `EnvironmentPanelTests`, `LivingEnvironmentAcceptanceRealDataTests` | [living environment](/engine/living-environment.md) |
| M8.1.4 UI foundation | `Developer > UI Lab` | `Destination-uiLab` | `UIOverlayEnabledControl`, `UILabSampleControl`, `UIStringsSampleControl` | `UIStatsLabel`, `UIStringsStatsLabel` | `UILabPanelTests`, `RendererUIFoundationAcceptanceTests` | [screen-space UI](/rendering/ui.md) |
| M8.2.5 SWF static render | `Developer > UI Lab > SWF movie` | `Destination-uiLab` | `SWFMovieControl`, `SWFLayerEnabledControl` | `SWFMovieStatsLabel` | `UILabPanelTests`, `RendererSWFStaticAcceptanceTests` | [screen-space UI](/rendering/ui.md) |
| M8.3.3 AS2 runtime | `Developer > UI Lab > SWF movie` then `Developer > UI Lab > SWF runtime` | `Destination-uiLab` | `SWFRuntimeStartControl`, `SWFRuntimeCallControl`, `SWFRuntimeCallInvokeControl`, `SWFRuntimeTickBurstControl`, `SWFRuntimeKeyControl`, `SWFRuntimeSendKeyControl` | `SWFRuntimeStatsLabel`, `SWFRuntimeInvokeStatsLabel`, `SWFRuntimeTallyStatsLabel` | `UILabPanelTests`, `RendererSWFInteractiveAcceptanceTests` | [screen-space UI](/rendering/ui.md) |
| M8.4.2 interaction target | `World > HUD & Interaction > Target` | `Destination-hudInteraction` | Live selection only — no forcing control | `HUDTargetStatsLabel` | `HUDInteractionPanelTests` | [interaction](/engine/interaction.md) |
| M8.4.3 HUD elements | `World > HUD & Interaction > Elements` | `Destination-hudInteraction` | `HUDLayerEnabledControl`, `HUDCrosshairControl`, `HUDMetersControl`, `HUDCompassControl`, `HUDMarkersControl`, `HUDPromptControl`, `HUDPlaceholderTextControl`, `HUDScaleControl` | `HUDElementsStatsLabel` | `HUDInteractionPanelTests`, `DestinationRegistryTests`, `HUDAcceptanceRealDataTests` | [screen-space UI](/rendering/ui.md) |
| M8.5.1 system menu | `World > System Menu` | `Destination-systemMenu` | `SystemMenuOpenControl`, `SystemMenuResumeControl`, `SystemMenuUpControl`, `SystemMenuDownControl`, `SystemMenuActivateControl`, `SystemMenuMovieControl`, `SystemMenuMasterVolumeControl` | `SystemMenuStatsLabel`, `SystemMenuDataRootStatsLabel`, `SystemMenuSettingsStatsLabel` | `SystemMenuPanelTests`, `SystemMenuAcceptanceRealDataTests` | [system menu](/engine/system-menu.md) |
| M8 overall acceptance | `World > World` (walk mode), `World > HUD & Interaction > Elements` and `> Target`, `Developer > UI Lab > UI foundation` (pause), `World > Environment > Sun shadows` (setting while paused), `World > System Menu > Menu` (second pause surface) | `Destination-world`, `Destination-hudInteraction`, `Destination-uiLab`, `Destination-environment`, `Destination-systemMenu` | `CameraMovementModeControl`, `HUDLayerEnabledControl`, `HUDCrosshairControl`, `UIMenuPushControl`, `UIMenuPopControl`, `SunShadowsEnabledControl`, `ShadowQualityControl`, `SystemMenuOpenControl`, `SystemMenuResumeControl` | `CameraStatsLabel`, `HUDElementsStatsLabel`, `HUDTargetStatsLabel`, `UIMenuStatsLabel`, `ShadowStatsLabel`, `SystemMenuStatsLabel`, plus the `Destination-<id>-OverrideIndicator` dots | `M8AcceptanceTests`, `DestinationRegistryTests`, `AppSidebarModelTests`, `WorldPanelTests`, `HUDInteractionPanelTests`, `UILabPanelTests`, `SystemMenuPanelTests`, `EnvironmentPanelTests` | [screen-space UI](/rendering/ui.md) |
| M9.1.3 audio | `World > Audio` | `Destination-audio` | `AudioEnabledControl`, `AudioMasterVolumeControl`, the generated `Audio<Category>VolumeControl` family, `AudioFileControl`, `AudioPlaySelectedControl`, `AudioStopAllControl` | `AudioStatsLabel`, `AudioSourcesStatsLabel` | `AudioPanelTests` | [audio](/engine/audio.md) |
| M9.2.2 world SFX + ambience | `World > Audio > SFX & Ambience` | `Destination-audio` | `AudioSfxEnabledControl`, `AudioAmbienceEnabledControl`, `AudioStopAmbienceControl`, `AudioEnabledControl` (Output section, starts the engine) | `AudioSfxStatsLabel` | `AudioPanelTests`, `DestinationRegistryTests`, `WorldAudioSoundDirectorTests`, `WorldAudioDirectorAmbienceTests`, `WorldAudioEngineTests`, `AudioSourceStreamerTests`, `AmbienceCatalogTests`, `CellStreamerTests` (cases in `CellStreamerAmbienceTests.swift`), `RecordDecoderTests` (cases in `ModelBaseSoundTests.swift`), `AcousticSpaceRecordTests`, `RegionRecordTests`, `CellRecordTests` | [world SFX + ambience](/engine/world-sfx.md) |
| M9.2.3 music playlists | `World > Audio > Music` | `Destination-audio` | `AudioMusicEnabledControl`, `AudioMusicTypeControl`, `AudioStopMusicControl`, `AudioEnabledControl` (Output section, starts the engine) | `AudioMusicStatsLabel` | `AudioPanelTests`, `DestinationRegistryTests`, `MusicCatalogTests`, `MusicCatalogPlaylistTests`, `WorldMusicDirectorTests`, `CellStreamerTests` (cases in `CellStreamerMusicTests.swift`), `MusicRecordTests`, `MusicRecordStoreTests` | [music playlists](/engine/music.md) |
| M9 overall acceptance | `World > Audio > Output`, `> Sources`, `> Music`, `> SFX & Ambience` | `Destination-audio` | `AudioEnabledControl`, the generated `Audio<Category>MuteControl` and `Audio<Category>SoloControl` families (`AudioEffectsMuteControl` and `AudioMusicSoloControl` are the two the gate clicks, reached as `outputSection.muteControls[.effects]` and `soloControls[.music]`), `AudioFileControl`, `AudioPlaySelectedControl`, `AudioStopAllControl`, `AudioMusicTypeControl`, `AudioStopMusicControl`, `AudioSfxEnabledControl`, `AudioStopAmbienceControl` | `AudioStatsLabel`, `AudioSourcesStatsLabel`, `AudioMusicStatsLabel`, `AudioSfxStatsLabel`, plus the `Destination-audio-OverrideIndicator` dot | `M9AcceptanceTests`, `WorldAudioTransitionAcceptanceTests`, `M9AudioAcceptanceRealDataTests` (env-gated, `make realtest`), `AudioPanelTests`, `AudioPanelMuteSoloTests`, `WorldAudioEngineMuteSoloTests`, `DestinationRegistryTests`, `AppSidebarModelTests`, `MusicRecordStoreTests`, `WorldMusicDirectorTests`, `CellStreamingFlyPathTests` (audio frame budget) | [audio](/engine/audio.md) |
| M10.1.5 runtime state | `World > Runtime State` | `Destination-runtimeState` | `RuntimeStateTargetControl`, `RuntimeStateDisableControl`, `RuntimeStateEnableControl`, `RuntimeStateNudgeControl`, `RuntimeStateResetTargetControl`, `RuntimeStateResetAllControl`, `RuntimeStateSlotControl`, `RuntimeStateSaveControl`, `RuntimeStateLoadControl` | `RuntimeStateStatsLabel`, `RuntimeStateJournalStatsLabel`, `RuntimeStateChangeStatsLabel`, `RuntimeStateResetStatsLabel`, `RuntimeStateSaveStatsLabel` | `M10StateAcceptanceTests`, `RuntimeStatePanelTests`, `DestinationRegistryTests` | [runtime state](/engine/runtime-state.md) |
| M10 overall acceptance | `World > Runtime State > Inspect`, `> Time`, `> Globals`, `> Conditions`, `> Change`, `> Reset`, `> Save`, plus `World > Environment > Weather` for the legacy time slider | `Destination-runtimeState`, `Destination-environment` | `RuntimeStateTargetControl`, `RuntimeStateDisableControl`, `RuntimeStateEnableControl`, `RuntimeStateNudgeControl`, `RuntimeStateResetTargetControl`, `RuntimeStateResetAllControl`, `RuntimeStateSlotControl`, `RuntimeStateSaveControl`, `RuntimeStateLoadControl`, `RuntimeStateHourControl`, `RuntimeStateDayControl`, `RuntimeStateMonthControl`, `RuntimeStateYearControl`, `RuntimeStateApplyDateControl`, `RuntimeStateTimescaleControl`, `RuntimeStateApplyTimescaleControl`, `RuntimeStateGlobalControl`, `RuntimeStateGlobalValueControl`, `RuntimeStateGlobalApplyControl`, `RuntimeStateGlobalResetControl`, `RuntimeStateConditionSourceControl`, `RuntimeStateConditionEvaluateControl`, `TimeOfDayControl` | `RuntimeStateStatsLabel`, `RuntimeStateJournalStatsLabel`, `RuntimeStateChangeStatsLabel`, `RuntimeStateResetStatsLabel`, `RuntimeStateSaveStatsLabel`, `RuntimeStateTimeStatsLabel`, `RuntimeStateGlobalsStatsLabel`, `RuntimeStateConditionStatsLabel`, `RuntimeStateConditionTallyStatsLabel`, `TimeOfDayStatsLabel`, plus the `Destination-runtimeState-OverrideIndicator` dot | `M10AcceptanceTests`, `M10StateAcceptanceTests`, `RuntimeStatePanelTests`, `RuntimeStatePanelTimeTests`, `RuntimeStatePanelGlobalsTests`, `RuntimeStatePanelConditionsTests`, `RuntimeStateConditionRunnerTests`, `GameViewControllerRuntimeStateJournalTests`, `DestinationRegistryTests`, `DestinationRegistryRuntimeStateTests`, `M10AcceptanceRealDataTests` (env-gated, `make realtest`) | [runtime state](/engine/runtime-state.md) |
| M11.1 headless VM | Headless by issue #170; `World > Scripts` deferred to M11.2 | — | — | `PapyrusTallySnapshot` (headless result, not an accessibility id) | `M11AcceptanceTests`, `PapyrusNativeRegistryTests`, `PapyrusSchedulerTests`, `PexNativeCensusTests`, `PapyrusAcceptanceRealDataTests` (env-gated, `make realtest`) | [Papyrus virtual machine](/engine/papyrus-vm.md) |
| M11.2.3 trigger volumes | `World > World > Triggers` | `Destination-world` | `TriggerLogClearControl`, `CameraMovementModeControl` (the walk-mode gate occupancy needs) | `TriggerVolumeStatsLabel`, `TriggerEventStatsLabel` | `WorldPanelTests`, `TriggerEventLogTests`, `DestinationRegistryTests` | [static collision world](/engine/collision-world.md) |
| M11 overall acceptance | `World > Scripts` | `Destination-scripts` | `ScriptPauseControl`, `ScriptStepControl`, `ScriptBurstControl` | `ScriptInstancesStatsLabel`, `ScriptEventsStatsLabel`, `ScriptSchedulerStatsLabel`, `ScriptNativeTallyStatsLabel` | `M11AcceptancePanelTests`, `M11AcceptanceEngineTests`, `M11ScriptedWorldAcceptanceTests`, `CellStreamingFlyPathTests`, `M11AcceptanceRealDataTests` (env-gated, `make realtest`) | [Papyrus virtual machine](/engine/papyrus-vm.md) |
| M12.1.3 world items | `World > HUD & Interaction > Items` | `Destination-hudInteraction` | `ItemsTakeControl`, `ItemsSearchControl`, `ItemsTakeAllControl`, `ItemsCloseContainerControl`, `ItemsDropControl`, `ItemsDropFormIDField`, `ItemsDropCountField` | `ItemsStatsLabel` | `ItemsSectionTests`, `DestinationRegistryTests`, `WorldItemRuntimeTests`, `ContainerSessionTests`, `CellSceneBuilderSpawnTests`, `CellStreamerSpawnTests`, `WorldItemRealDataTests` (env-gated, `make realtest`) | [interaction](/engine/interaction.md) |
| M12.2.1 equipment | `World > HUD & Interaction > Items` | `Destination-hudInteraction` | `ItemsEquipControl`, `ItemsUnequipControl`, `ItemsEquipFormIDField`, `ItemsEquipTargetControl` | `ItemsStatsLabel` | `ItemsSectionTests`, `DestinationRegistryTests`, `EquipmentRuntimeTests`, `ActorEquipmentVisualTests`, `CellSceneBuilderEquipmentTests`, `RigidAttachmentTests`, `ActorEquipmentSwapTests`, `AppearanceRecordDecodeTests`, `ActorEquipmentRealDataTests` (env-gated, `make realtest`) | [actor records](/formats/actors.md) |
| M12.2.2 inventory menu | `World > Inventory Menu > Menu` | `Destination-inventoryMenu` | `InventoryMenuOpenControl`, `InventoryMenuCloseControl`, `InventoryMenuUpControl`, `InventoryMenuDownControl`, `InventoryMenuPreviousCategoryControl`, `InventoryMenuNextCategoryControl`, `InventoryMenuEquipControl`, `InventoryMenuDropControl`, `InventoryMenuMovieControl` | `InventoryMenuStatsLabel` | `InventoryMenuPanelTests`, `InventoryMenuModelTests`, `SWFMovieImportMergeTests`, `DestinationRegistryTests`, `AppSidebarModelTests`, `InventoryMenuAcceptanceRealDataTests` (env-gated, `make realtest`) | [inventory menu](/engine/inventory-menu.md) |
| M12.2.3 container + barter menus | `World > Container Menu > Merchant` and `> Menu` | `Destination-containerMenu` | `ContainerMerchantSelectControl`, `ContainerMerchantCrosshairControl`, `ContainerMenuOpenControl`, `ContainerMenuCloseControl`, `ContainerMenuUpControl`, `ContainerMenuDownControl`, `ContainerMenuSwitchSideControl`, `ContainerMenuTransferControl`, `ContainerMenuTakeAllControl`, `ContainerMenuBarterControl`, `ContainerMenuMovieControl` | `ContainerMenuStatsLabel`, `ContainerMerchantStatsLabel` | `ContainerMenuPanelTests`, `ContainerMenuModelTests`, `BarterPricingTests`, `BarterSessionTests`, `DestinationRegistryTests`, `AppSidebarModelTests`, `ContainerMenuAcceptanceRealDataTests` (env-gated, `make realtest`) | [container and barter menus](/engine/barter.md) |

`World > World` (`Destination-world`, controls `CameraMovementModeControl`,
`CameraCopyPoseControl`, readouts `CameraStatsLabel`, `FrameStatsLabel`,
`SceneStatsLabel`) is the launch destination, exercised by `WorldPanelTests` and, since
the M8 gate, part of the M8 overall acceptance row above.

One caveat is recorded with that row: `CameraStatsLabel` prints position, orientation, and
cell, not the movement mode, so walk mode is proven by the selector's own state
(`CameraMovementModeControl` reading `Walk`) plus the sidebar row's
`Destination-world-OverrideIndicator` turning on, which is what a user sees. A readout
that names the mode would be a cheaper check; it does not exist yet.

Settings is deliberately not a sidebar destination — it is the standard Cmd+, window — so
it never appears as an acceptance path.
