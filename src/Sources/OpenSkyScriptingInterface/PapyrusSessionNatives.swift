public import OpenSkyConditions
public import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyPerceptionInterface
public import OpenSkyWorldState

/// Clock, conditions, packages, cell, physics, and the renderer's poses.
public struct PapyrusSessionNatives {
    /// The clock the five time globals project from, as every other `GlobalResolution` does.
    public var clockSource: (() -> GameClock?)?
    /// Seconds of real time since the session started, for `Utility.GetCurrentRealTime`.
    /// The shell passes it in, so a test can fix the time.
    public var realTimeSource: (() -> Double)?
    /// Picks the log entry a stage runs, and answers the condition-twin natives.
    /// Nil runs every log entry.
    public var conditionEvaluator: (() -> ConditionEvaluator)?
    /// For `GetCurrentLocation`, `GetParentCell`, and `GetWorldSpace`.
    public var conditionData: (() -> ConditionDataResolution)?
    /// The PACK an actor runs now, as a load-order FormID, for `GetCurrentPackage`.
    public var currentPackage: ((ReferenceKey) -> FormID?)?
    /// A PACK's `PKCU` template, for `Package.GetTemplate`.
    public var packageTemplate: ((FormID) -> FormID?)?
    /// Changes a cell's fog; false when the cell is not the loaded interior.
    public var cellFog: ((FormID, PapyrusFogChange) -> Bool)?
    /// Kilograms of a body Havok moves, or nil when none does.
    public var havokMass: ((ReferenceKey) -> Float?)?
    /// Hands the drawn pose of every moving reference to the renderer, after each change.
    public var publishTranslationPoses: (([ReferenceKey: ReferenceTransformOverride]) -> Void)?
    /// The unit direction from the player toward the sun; nil indoors or while it is down.
    public var towardSun: (() -> SIMD3<Float>?)?
    /// Where the player's eyes are and the unit direction they look in.
    public var playerView: (() -> PapyrusPlayerView?)?
    /// `Weather.GetSkyMode`: 0 no sky, 1 interior, 2 sky dome only, 3 full sky.
    public var skyMode: (() -> Int32)?
    /// The VMAD scripts of an item's base record, for `OnEquipped` and `OnRead`.
    public var itemScripts: ((ReferenceKey) -> [AttachedScript])?
    /// The shared roller's script changes; nil in a session without leveled lists.
    public var leveledEdits: (() -> LeveledScriptEdits?)?

    public init() {}
}

/// What a script changed in the story that the session reacts to.
public struct PapyrusStoryNatives {
    /// A script started a quest, after its start-up stage: begin-on-start scenes start.
    public var questStarted: ((FormID) -> Void)?
    /// A stage item's Fail Quest flag failed a quest.
    public var questFailed: ((FormID) -> Void)?
    /// `SetDoingFavor` changed an actor's favour state: true on entry, false on exit.
    public var favorStateChanged: ((ReferenceKey, Bool) -> Void)?

    public init() {}
}

/// The player's eye and look direction.
nonisolated public struct PapyrusPlayerView: Equatable, Sendable {
    public let eye: SIMD3<Float>
    public let forward: SIMD3<Float>

    public init(eye: SIMD3<Float>, forward: SIMD3<Float>) {
        self.eye = eye
        self.forward = forward
    }
}
