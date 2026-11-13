// The handler slots of each streamer event. The enum order is the delivery
// order, so the order of the wiring statements cannot change behaviour, and
// each slot takes one handler (`FrameSchedule`).

public import OpenSkyCells
public import OpenSkyGameData
public import OpenSkyWorldInterface

/// The player entered or left a trigger volume.
public enum TriggerTransitionStep: Int, FramePhase {
    /// The readout log, which the streamer registers itself.
    case readout
    /// Papyrus `OnTriggerEnter` and `OnTriggerLeave`.
    case scripts
}

public enum WorldspaceChangeStep: Int, FramePhase {
    case weather
}

public enum CellHazardStep: Int, FramePhase {
    case hazards
}

/// One cell that joined the live world. `isFirstIntegration` is false for a
/// rebuild or an interior refresh, so scripts attach once.
public struct CellAttachment {
    public let scene: CellScene
    public let isFirstIntegration: Bool

    public init(scene: CellScene, isFirstIntegration: Bool) {
        self.scene = scene
        self.isFirstIntegration = isFirstIntegration
    }
}

extension CellStreamer {
    /// Runs `step` in its phase each time a cell joins the composition.
    public func registerCellAttached(
        _ phase: CellAttachStep, _ step: @escaping (CellAttachment) -> Void
    ) {
        events.onCellAttached.register(phase, step)
    }
}
