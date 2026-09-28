// World > AI & Navigation destination panel (issue #203, roadmap item 16.8):
// the sidebar verification surface for the whole M16 mind, composed from
// sections items 16.3 through 16.7 each specified a provider seam for.
//
// A destination of its own rather than more sections under `World > Combat &
// Physics`. Six sections and six readouts is past the promotion threshold in
// docs/tools/app-ui.md, the M16 gate names this path top-level (which outranks
// the threshold anyway), and the two destinations answer different questions: a
// fight is what one opponent in front of you is doing, and this is what one
// named actor in a crowd is doing all day.
//
// Section order follows the order a session uses them in: switch on what you
// want to see, choose whom you are watching, send it somewhere, read the
// schedule it keeps on its own, read what it notices, and read what it does when
// what it notices is an enemy.

import AppKit

final class AINavigationPanelViewController: InspectorPanelViewController {
    let overlaySection = AIOverlaySection()
    let actorSection = AIActorSection()
    let movementSection = AIMovementSection()
    let packageSection = AIPackageSection()
    let detectionSection = AIDetectionSection()
    let combatSection = AICombatSection()

    /// Weak throughout, for the reason every other panel holds its providers
    /// weakly: the game controller owns this panel's parent and the renderer,
    /// so the panel must not retain back.
    weak var overlayProvider: (any AIOverlayControlProviding)? {
        didSet { overlaySection.provider = overlayProvider }
    }

    /// The shared selection. Four sections read it, so it is assigned to all of
    /// them from one place rather than being threaded through each.
    weak var navigationProvider: (any AINavigationControlProviding)? {
        didSet {
            actorSection.provider = navigationProvider
            movementSection.provider = navigationProvider
            packageSection.provider = navigationProvider
            detectionSection.selectionProvider = navigationProvider
            combatSection.selectionProvider = navigationProvider
        }
    }

    weak var perceptionProvider: (any PerceptionControlProviding)? {
        didSet { detectionSection.provider = perceptionProvider }
    }

    weak var combatProvider: (any CombatLoopControlProviding)? {
        didSet { combatSection.provider = combatProvider }
    }

    override func makeSections() -> [PanelSectionViewController] {
        [
            overlaySection, actorSection, movementSection,
            packageSection, detectionSection, combatSection
        ]
    }

    /// Control forwards for the verification-surface tests, mirroring
    /// `CombatPhysicsPanelViewController`'s convention.
    var navmeshOverlayControl: NSButton {
        overlaySection.navmeshControl
    }

    var pathOverlayControl: NSButton {
        overlaySection.pathControl
    }

    var detectionOverlayControl: NSButton {
        overlaySection.detectionControl
    }

    var actorSelectControl: NSPopUpButton {
        actorSection.actorControl
    }

    var actorCrosshairControl: NSButton {
        actorSection.crosshairControl
    }

    var moveToCrosshairControl: NSButton {
        movementSection.moveControl
    }

    var moveStopControl: NSButton {
        movementSection.stopControl
    }

    var packageReevaluateControl: NSButton {
        packageSection.reevaluateControl
    }

    var hostilityControl: NSButton {
        combatSection.hostilityControl
    }
}
