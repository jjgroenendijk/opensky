// World > Player & Locomotion (docs/engine/locomotion-graph.md). Sections
// follow a session: where the player is, the graph state, the keys, the motion
// source, then controls that force a hard-to-reach state. The camera-mode popup
// is also here because it starts the simulation these readouts describe.

import AppKit
import OpenSkyWorld

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
