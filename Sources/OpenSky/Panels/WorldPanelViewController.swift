// World: the live render itself. Where the camera is, how fast the frame is,
// and what it drew. Each section reaches the renderer through its own narrow
// provider protocol.

import AppKit
import OpenSkyPhysics
import OpenSkyRendering
import OpenSkyWorld

final class WorldPanelViewController: InspectorPanelViewController {
    let cameraSection = CameraSection()
    let cinematicSection = CinematicCameraSection()
    let loadingSection = LoadingScreenSection()
    let firstPersonSection = FirstPersonSection()
    let frameSection = FrameStatsSection()
    let worldLoadSection = WorldLoadSection()
    let sceneSection = SceneStatsSection()
    let triggerSection = TriggerVolumeSection()
    let trapSection = TrapSection()
    let renderDebugSection = RenderDebugSection()

    /// Weak: the game controller owns this panel's parent and the renderer, so
    /// the panel must not retain back.
    weak var cameraProvider: (any CameraControlProviding)? {
        didSet { cameraSection.provider = cameraProvider }
    }

    /// First-person arms, field of view, and their readout. Here because this
    /// panel selects the camera mode.
    /// Kill cams and camera shots, beside the camera mode they take over.
    weak var cinematicProvider: (any CinematicCameraControlProviding)? {
        didSet { cinematicSection.provider = cinematicProvider }
    }

    /// Loading screens cover door transitions, which move this panel's camera.
    weak var loadingProvider: (any LoadingScreenControlProviding)? {
        didSet { loadingSection.provider = loadingProvider }
    }

    weak var firstPersonProvider: (any FirstPersonControlProviding)? {
        didSet { firstPersonSection.provider = firstPersonProvider }
    }

    weak var frameStatsProvider: (any FrameStatsProviding)? {
        didSet { frameSection.provider = frameStatsProvider }
    }

    /// Launch cost, beside the per-frame cost above it.
    weak var worldLoadProvider: (any WorldLoadReportProviding)? {
        didSet { worldLoadSection.provider = worldLoadProvider }
    }

    weak var sceneStatsProvider: (any SceneStatsProviding)? {
        didSet { sceneSection.provider = sceneStatsProvider }
    }

    /// Trigger-volume counts and occupancy. Here because occupancy needs walk
    /// mode, which this panel's Camera section selects.
    weak var triggerProvider: (any TriggerControlProviding)? {
        didSet { triggerSection.provider = triggerProvider }
    }

    /// Trap triggers, their enable chains, and live hazards, beside the volumes they use.
    weak var trapProvider: (any TrapControlProviding)? {
        didSet { trapSection.provider = trapProvider }
    }

    /// The render debug channel and the layer mask: both are views of the
    /// frame this panel reports on.
    weak var renderDebugProvider: (any RenderDebugControlProviding)? {
        didSet { renderDebugSection.provider = renderDebugProvider }
    }

    override func makeSections() -> [PanelSectionViewController] {
        [
            cameraSection, cinematicSection, firstPersonSection, frameSection, worldLoadSection,
            sceneSection, renderDebugSection, triggerSection, trapSection, loadingSection
        ]
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

    var renderDebugModeControl: NSPopUpButton {
        renderDebugSection.modeControl
    }

    var renderDebugSoloControl: NSPopUpButton {
        renderDebugSection.soloControl
    }
}
