// The handler slots of each streamer event. The enum order is the delivery
// order, so the order of the wiring statements cannot change behaviour, and
// each slot takes one handler (`FrameSchedule`).

import OpenSkyCells
import OpenSkyGameData

/// A use-key activation that passed the gate.
public enum InteractionStep: Int, FramePhase {
    /// The engine's own activation sound comes first.
    case audio
    /// Papyrus `OnActivate`.
    case scripts
    /// Last but one: the sound and the recorded activation land before the item leaves.
    case worldItems
    /// Agent control's event tap reads the outcome of the steps above.
    case agentEvents
}

/// A use-key press the gate refused.
public enum ActivationRefusalStep: Int, FramePhase {
    case lockpicking
    case mount
    case notice
    case agentEvents
}

/// The checks a press passes before it activates. The first refusal wins.
public enum ActivationGateStep: Int, FramePhase {
    /// A rider cannot open a door.
    case mount
    /// A beast cannot take items or talk.
    case beastForm
    case lock
    /// Actor state, used furniture, parent activation, and combat (`ActivationRefusalRule`).
    case notice
}

/// The player entered or left a trigger volume.
public enum TriggerTransitionStep: Int, FramePhase {
    /// The readout log, which the streamer registers itself.
    case readout
    /// Papyrus `OnTriggerEnter` and `OnTriggerLeave`.
    case scripts
}

/// A cell joined the live world.
public enum CellAttachStep: Int, FramePhase {
    /// Cell reset decides which references reset before the scripts see the cell.
    case resetPrepare
    /// Each new or reset actor and container freezes the level its leveled lists roll at.
    case leveledRolls
    /// The scripts attach to the cell's references.
    case scripts
    /// The reset events queue after the scripts attached.
    case resetEnqueue
    case agentEvents
}

/// A cell left the live world.
public enum CellDetachStep: Int, FramePhase {
    case scripts
    case reset
    case agentEvents
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
