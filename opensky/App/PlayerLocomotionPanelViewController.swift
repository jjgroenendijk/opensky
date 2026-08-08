// World > Player & Locomotion destination panel (issue #191): the sidebar
// verification surface for the M14 player. Thin composition of self-contained
// sections on the shared panel framework, the same shape as
// JournalPanelViewController. Exact sidebar path and control ids:
// docs/engine/behavior-runtime.md.
//
// Section order follows the order a session reaches for them: where the player
// is, what the graph made of it, which keys drive it, where the motion came
// from, and finally the two controls that force a state the route is awkward to
// reach.
//
// It is a destination of its own rather than sections under `World > World`
// because locomotion is a subsystem with five readouts, and the camera panel is
// about where the eye is rather than what the player is doing. The camera-mode
// popup appears on both, deliberately: it is the switch that starts the
// simulation these readouts describe.
//
// Melee, Archery and Death & Ragdoll sat here through items 15.4, 15.5 and
// 15.6, each noting that the M15 gate panel was where a `Combat & Physics`
// destination belonged if the surface outgrew this one. Item 15.9 is that gate
// and the surface did outgrow it — six combat and physics sections against this
// panel's five locomotion ones — so the three moved to
// `World > Combat & Physics` and this panel is locomotion again.

import AppKit

final class PlayerLocomotionPanelViewController: InspectorPanelViewController {
    let stateSection = LocomotionStateSection()
    let graphSection = LocomotionGraphSection()
    let bindingsSection = LocomotionBindingsSection()
    let motionSection = LocomotionMotionSection()
    let devSection = LocomotionDevSection()

    /// Live locomotion bridge. Weak: the game controller owns this panel's
    /// parent and the renderer, so the panel must not retain back.
    weak var provider: (any PlayerLocomotionControlProviding)? {
        didSet {
            stateSection.provider = provider
            graphSection.provider = provider
            bindingsSection.provider = provider
            motionSection.provider = provider
            devSection.provider = provider
        }
    }

    /// Camera mode rides its own seam, which only the State section reads.
    weak var cameraProvider: (any CameraControlProviding)? {
        didSet { stateSection.cameraProvider = cameraProvider }
    }

    override func makeSections() -> [PanelSectionViewController] {
        [stateSection, graphSection, bindingsSection, motionSection, devSection]
    }

    /// Control forwards for the verification-surface tests, mirroring
    /// JournalPanelViewController's convention.
    var cameraModeControl: NSPopUpButton {
        stateSection.cameraModeControl
    }

    var sneakControl: NSButton {
        bindingsSection.sneakControl
    }

    var jumpControl: NSButton {
        bindingsSection.jumpControl
    }

    var clearTraceControl: NSButton {
        motionSection.clearTraceControl
    }

    var forcedGaitControl: NSPopUpButton {
        devSection.forcedGaitControl
    }

    var raiseEventControl: NSButton {
        devSection.raiseEventControl
    }
}
