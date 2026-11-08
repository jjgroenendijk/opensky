public import OpenSkyGameData

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
