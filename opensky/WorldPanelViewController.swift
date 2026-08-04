// World destination panel: the sidebar surface for the live render itself —
// where the camera is, how fast the frame is, and what the frame drew. The
// sidebar row used to be a bare "Viewport" that only collapsed the inspector
// column, which told a first-time user nothing and offered no controls; the
// bare render is still reachable, now as a View-menu mode rather than a
// destination (docs/tools/app-ui.md).
//
// Same shape as EnvironmentPanelViewController: a thin composition of
// self-contained sections, each talking to the live renderer through its own
// narrow provider protocol.

import AppKit

final class WorldPanelViewController: InspectorPanelViewController {
    let cameraSection = CameraSection()
    let firstPersonSection = FirstPersonSection()
    let frameSection = FrameStatsSection()
    let sceneSection = SceneStatsSection()
    let triggerSection = TriggerVolumeSection()

    /// Weak: the game controller owns this panel's parent and the renderer, so
    /// the panel must not retain back.
    weak var cameraProvider: (any CameraControlProviding)? {
        didSet { cameraSection.provider = cameraProvider }
    }

    /// The first-person arms, field of view, and their readout (issue #190).
    /// Wired here because first person is a camera mode this panel already
    /// selects.
    weak var firstPersonProvider: (any FirstPersonControlProviding)? {
        didSet { firstPersonSection.provider = firstPersonProvider }
    }

    weak var frameStatsProvider: (any FrameStatsProviding)? {
        didSet { frameSection.provider = frameStatsProvider }
    }

    weak var sceneStatsProvider: (any SceneStatsProviding)? {
        didSet { sceneSection.provider = sceneStatsProvider }
    }

    /// Trigger-volume accounting and occupancy (issue #173). It lives here
    /// because occupancy is a walk-mode behaviour and the fly/walk selector is
    /// in this panel's Camera section.
    weak var triggerProvider: (any TriggerControlProviding)? {
        didSet { triggerSection.provider = triggerProvider }
    }

    override func makeSections() -> [PanelSectionViewController] {
        [cameraSection, firstPersonSection, frameSection, sceneSection, triggerSection]
    }

    /// Control forwards for the verification-surface tests, matching the
    /// Environment panel's convention.
    var cameraMovementModeControl: NSPopUpButton {
        cameraSection.movementModeControl
    }

    var cameraCopyPoseControl: NSButton {
        cameraSection.copyPoseControl
    }

    var firstPersonArmsEnabledControl: NSButton {
        firstPersonSection.armsEnabledControl
    }

    var firstPersonFOVControl: NSSlider {
        firstPersonSection.fovControl
    }

    var triggerLogClearControl: NSButton {
        triggerSection.clearLogControl
    }
}
