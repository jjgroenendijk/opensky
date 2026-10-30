// The session scope answers every adapter's host protocol, so each adapter sees
// only the part of the session it reads.

import AppKit

extension GameSessionScope: @MainActor AIWorldHost {}
extension GameSessionScope: @MainActor ActorGraphWorldHost {}
extension GameSessionScope: @MainActor ActorWorldHost {}
extension GameSessionScope: @MainActor AgentWorldHost {}
extension GameSessionScope: @MainActor AnimationEventWorldHost {}
extension GameSessionScope: @MainActor AudioWorldHost {}
extension GameSessionScope: @MainActor BenchmarkWorldHost {}
extension GameSessionScope: @MainActor CinematicCameraWorldHost {}
extension GameSessionScope: @MainActor CombatWorldHost {}
extension GameSessionScope: @MainActor ContainerMenuHost {}
extension GameSessionScope: @MainActor CrimeWorldHost {}
extension GameSessionScope: @MainActor DialogueCameraHost {}
extension GameSessionScope: @MainActor DialogueMenuHost {}
extension GameSessionScope: @MainActor DialogueWorldHost {}
extension GameSessionScope: @MainActor EffectGraphWorldHost {}
extension GameSessionScope: @MainActor EffectsWorldHost {}
extension GameSessionScope: @MainActor IdleWorldHost {}
extension GameSessionScope: @MainActor InventoryMenuHost {}
extension GameSessionScope: @MainActor InventoryWorldHost {}
extension GameSessionScope: @MainActor JournalMenuHost {}
extension GameSessionScope: @MainActor LoadingScreenWorldHost {}
extension GameSessionScope: @MainActor LockWorldHost {}
extension GameSessionScope: @MainActor PerkActivationWorldHost {}
extension GameSessionScope: @MainActor LockpickingMenuHost {}
extension GameSessionScope: @MainActor MagicWorldHost {}
extension GameSessionScope: @MainActor MapWorldHost {}
extension GameSessionScope: @MainActor MenuRouterHost {}
extension GameSessionScope: @MainActor MenuScreensHost {}
extension GameSessionScope: @MainActor MenuScreensWorldHost {}
extension GameSessionScope: @MainActor MenuSoundHost {}
extension GameSessionScope: @MainActor MenuWorldHost {}
extension GameSessionScope: @MainActor MessageWorldHost {}
extension GameSessionScope: @MainActor MovieWorldHost {}
extension GameSessionScope: @MainActor ObjectAnimationWorldHost {}
extension GameSessionScope: @MainActor PlayerWorldHost {}
extension GameSessionScope: @MainActor ProgressionWorldHost {}
extension GameSessionScope: @MainActor RagdollWorldHost {}
extension GameSessionScope: @MainActor RuntimeStateWorldHost {}
extension GameSessionScope: @MainActor SaveGameWorldHost {}
extension GameSessionScope: @MainActor SkyrimSaveExportHost {}
extension GameSessionScope: @MainActor SkyrimSaveImportHost {}
extension GameSessionScope: @MainActor ScriptWorldHost {}
extension GameSessionScope: @MainActor StoryWorldHost {}
extension GameSessionScope: @MainActor VehicleWorldHost {}
extension GameSessionScope: @MainActor MountWorldHost {}
extension GameSessionScope: @MainActor BeastFormWorldHost {}
extension GameSessionScope: @MainActor DragonFlightWorldHost {}
extension GameSessionScope: @MainActor WorldSessionWiringHost {}
