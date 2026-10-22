// World > Player & Locomotion (docs/engine/locomotion-graph.md). Sections follow a
// session: where the player is, the graph state, the actor state it shares with the
// engine, the mount, the keys, the motion source, then controls that force a hard-to-reach
// state. The camera-mode popup is here because it starts the simulation.

import AppKit
import OpenSkyPlayer
import OpenSkyWorld

final class PlayerLocomotionPanelViewController: InspectorPanelViewController {
    let stateSection = LocomotionStateSection()
    let graphSection = LocomotionGraphSection()
    let actorStateSection = LocomotionActorStateSection()
    let mountSection = LocomotionMountSection()
    let bindingsSection = LocomotionBindingsSection()
    let motionSection = LocomotionMotionSection()
    let devSection = LocomotionDevSection()

    /// Live locomotion bridge. Weak: the game controller owns this panel's
    /// parent and the renderer, so the panel must not retain back.
    weak var provider: (any PlayerLocomotionControlProviding)? {
        didSet {
            stateSection.provider = provider
            graphSection.provider = provider
            actorStateSection.provider = provider
            bindingsSection.provider = provider
            motionSection.provider = provider
            devSection.provider = provider
        }
    }

    weak var mountProvider: (any MountControlProviding)? {
        didSet { mountSection.provider = mountProvider }
    }

    /// Camera mode rides its own seam, which only the State section reads.
    weak var cameraProvider: (any CameraControlProviding)? {
        didSet { stateSection.cameraProvider = cameraProvider }
    }

    override func makeSections() -> [PanelSectionViewController] {
        [
            stateSection, graphSection, actorStateSection, mountSection, bindingsSection,
            motionSection, devSection
        ]
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

    var mountNearestControl: NSButton {
        mountSection.mountNearestControl
    }

    var dismountControl: NSButton {
        mountSection.dismountControl
    }

    var raiseEventControl: NSButton {
        devSection.raiseEventControl
    }
}
