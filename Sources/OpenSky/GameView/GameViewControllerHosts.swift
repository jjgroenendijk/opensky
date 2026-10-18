// The composition root: the controller is the one type that holds every session
// part, and each adapter sees it only through its own host protocol.

import AppKit

extension GameViewController: @MainActor AIWorldHost {}
extension GameViewController: @MainActor ActorWorldHost {}
extension GameViewController: @MainActor AgentWorldHost {}
extension GameViewController: @MainActor AnimationEventWorldHost {}
extension GameViewController: @MainActor AudioWorldHost {}
extension GameViewController: @MainActor CinematicCameraWorldHost {}
extension GameViewController: @MainActor CombatWorldHost {}
extension GameViewController: @MainActor ContainerMenuHost {}
extension GameViewController: @MainActor CrimeWorldHost {}
extension GameViewController: @MainActor DialogueCameraHost {}
extension GameViewController: @MainActor DialogueMenuHost {}
extension GameViewController: @MainActor DialogueWorldHost {}
extension GameViewController: @MainActor EffectsWorldHost {}
extension GameViewController: @MainActor IdleWorldHost {}
extension GameViewController: @MainActor InventoryMenuHost {}
extension GameViewController: @MainActor InventoryWorldHost {}
extension GameViewController: @MainActor JournalMenuHost {}
extension GameViewController: @MainActor LoadingScreenWorldHost {}
extension GameViewController: @MainActor LockWorldHost {}
extension GameViewController: @MainActor LockpickingMenuHost {}
extension GameViewController: @MainActor MagicWorldHost {}
extension GameViewController: @MainActor MapWorldHost {}
extension GameViewController: @MainActor MenuRouterHost {}
extension GameViewController: @MainActor MenuScreensHost {}
extension GameViewController: @MainActor MenuScreensWorldHost {}
extension GameViewController: @MainActor MenuSoundHost {}
extension GameViewController: @MainActor MenuWorldHost {}
extension GameViewController: @MainActor MessageWorldHost {}
extension GameViewController: @MainActor ObjectAnimationWorldHost {}
extension GameViewController: @MainActor PlayerWorldHost {}
extension GameViewController: @MainActor ProgressionWorldHost {}
extension GameViewController: @MainActor RagdollWorldHost {}
extension GameViewController: @MainActor RuntimeStateWorldHost {}
extension GameViewController: @MainActor SaveGameWorldHost {}
extension GameViewController: @MainActor SkyrimSaveExportHost {}
extension GameViewController: @MainActor SkyrimSaveImportHost {}
extension GameViewController: @MainActor ScriptWorldHost {}
extension GameViewController: @MainActor StoryWorldHost {}
extension GameViewController: @MainActor VehicleWorldHost {}
extension GameViewController: @MainActor WorldSessionWiringHost {}

extension GameViewController {
    /// `NSViewController.view` is settable, so a read-only host requirement takes this name.
    var hostView: NSView {
        view
    }
}
