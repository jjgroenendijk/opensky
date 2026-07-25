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
    let frameSection = FrameStatsSection()
    let sceneSection = SceneStatsSection()

    /// Weak: the game controller owns this panel's parent and the renderer, so
    /// the panel must not retain back.
    weak var cameraProvider: (any CameraControlProviding)? {
        didSet { cameraSection.provider = cameraProvider }
    }

    weak var frameStatsProvider: (any FrameStatsProviding)? {
        didSet { frameSection.provider = frameStatsProvider }
    }

    weak var sceneStatsProvider: (any SceneStatsProviding)? {
        didSet { sceneSection.provider = sceneStatsProvider }
    }

    override func makeSections() -> [PanelSectionViewController] {
        [cameraSection, frameSection, sceneSection]
    }

    /// Control forwards for the verification-surface tests, matching the
    /// Environment panel's convention.
    var cameraMovementModeControl: NSPopUpButton {
        cameraSection.movementModeControl
    }

    var cameraCopyPoseControl: NSButton {
        cameraSection.copyPoseControl
    }
}
