// The script calls that are running or waiting at a save, in a form with no runtime
// handle in it. The save writes them as `PCAL`.
// docs/engine/papyrus-world.md#script-state-in-a-save.

public import OpenSkyFormatsESM

/// A value of a saved call. An object is named by what it stands for in the world.
nonisolated public enum PapyrusSavedValue: Equatable, Sendable {
    case none
    case boolean(Bool)
    case integer(Int32)
    case float(Float)
    case string(String)
    /// A script instance.
    case instance(PapyrusInstanceKey)
    /// A reference or a form with no script of its own type on it.
    case reference(ReferenceKey)
    /// One alias of a quest.
    case alias(quest: ReferenceKey, id: UInt32)
    /// An index into `PapyrusCallSnapshot.arrays`. Two values with one index share
    /// the array, as they did before the save.
    case array(Int)
}

nonisolated public struct PapyrusSavedArray: Equatable, Sendable {
    public var elementType: String
    public var elements: [PapyrusSavedValue]

    public init(elementType: String, elements: [PapyrusSavedValue]) {
        self.elementType = elementType
        self.elements = elements
    }
}

/// Where a returned value goes.
nonisolated public enum PapyrusSavedReturn: Equatable, Sendable {
    /// The call that started the stack: the value is the result of the whole call.
    case root
    case discard
    /// A variable of the frame below, or nil for a value nobody reads.
    case assign(String?)
}

/// One function of the call stack.
nonisolated public struct PapyrusFrameState: Equatable, Sendable {
    /// The script that declares the function, and the function's place in it.
    public var script: String
    public var functionOrdinal: Int
    /// The function's instruction count, to tell a changed script from the saved one.
    public var instructionCount: Int
    /// `Self` in the function, or nil in a global function.
    public var instance: PapyrusInstanceKey?
    public var completion: PapyrusSavedReturn
    public var instructionIndex: Int
    public var slots: [PapyrusSavedValue]

    public init(
        script: String, functionOrdinal: Int, instructionCount: Int,
        instance: PapyrusInstanceKey?, completion: PapyrusSavedReturn
    ) {
        self.script = script
        self.functionOrdinal = functionOrdinal
        self.instructionCount = instructionCount
        self.instance = instance
        self.completion = completion
        instructionIndex = 0
        slots = []
    }
}

/// What a saved call waits for.
nonisolated public enum PapyrusSavedWake: Equatable, Sendable {
    /// World time in real seconds, then the answer, or the return type's default.
    case realSeconds(Double, answer: PapyrusSavedValue?)
    /// Real seconds that also pass in a menu.
    case menuSeconds(Double)
    case gameHours(Double)
    /// The fragments of the quest's stage, then this answer.
    case questFragments(quest: ReferenceKey, answer: PapyrusSavedValue)
    /// The queued start of the quest, and then its stage fragments when asked.
    case questStart(quest: ReferenceKey, thenFragments: Bool)
    /// Something the save does not keep, such as an animation. The call goes on at the
    /// next step with the return type's default.
    case lost
}

nonisolated public struct PapyrusCallState: Equatable, Sendable {
    /// The instance whose event started the call.
    public var owner: PapyrusInstanceKey?
    /// A used-up slice holds its instance; a latent call does not.
    public var holdsInstance = false
    /// The native function the call waits in, and its return type.
    public var nativeScript = ""
    public var nativeFunction = ""
    public var returnType = ""
    public var wake: PapyrusSavedWake
    /// Where the native's answer goes in the top frame.
    public var resume: PapyrusSavedReturn
    /// Bottom of the stack first.
    public var frames: [PapyrusFrameState]

    public init(wake: PapyrusSavedWake, resume: PapyrusSavedReturn, frames: [PapyrusFrameState]) {
        self.wake = wake
        self.resume = resume
        self.frames = frames
    }
}

/// Every saved call, oldest first, with the arrays they share.
nonisolated public struct PapyrusCallSnapshot: Equatable, Sendable {
    public var arrays: [PapyrusSavedArray] = []
    public var calls: [PapyrusCallState] = []

    public static let empty = Self()

    public init() {}

    public var isEmpty: Bool {
        calls.isEmpty
    }
}
