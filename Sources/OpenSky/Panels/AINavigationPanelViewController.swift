// World > AI & Navigation: the sidebar surface for actor AI. It is its own
// destination because it answers what one named actor does all day, not what
// one opponent does in a fight. Sections follow a session: switch on, pick an
// actor, send it, read its schedule, perception, and combat reaction.

import AppKit
import OpenSkyCombat
import OpenSkyPerceptionInterface
import OpenSkyWorld

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
