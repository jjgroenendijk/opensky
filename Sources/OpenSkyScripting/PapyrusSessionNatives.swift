// The player, perception, and session families of the Papyrus world bridge. As in
// `PapyrusActorNatives.swift`, a nil member is a session without that runtime.

import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyPerceptionInterface
import OpenSkyWorldState

/// The player controls a few natives drive.
public struct PapyrusPlayerNatives {
    /// For `GetPlayersLastRiddenHorse`.
    public var playersLastMount: (() -> ReferenceKey?)?
    /// For `Actor.Dismount`: true when a dismount started.
    public var dismount: ((ReferenceKey) -> Bool)?
    /// For `StartSneaking`.
    public var togglePlayerSneaking: (() -> Void)?
    /// Shows or hides the HUD, for `Debug.ToggleMenus`.
    public var toggleMenus: (() -> Void)?

    public init() {}
}

/// What actors see and where they stand.
public struct PapyrusPerceptionNatives {
    /// What perception knows about pairs of actors, for `HasLOS` and `IsDetectedBy`.
    public var detection: (() -> DetectionResolution?)?
    /// The 0...1 light detection reads on an actor whose feet are here.
    public var lightLevel: ((SIMD3<Float>) -> Float)?
    /// Whether the viewer sees the target now, for the `RegisterForLOS` family.
    /// See docs/engine/papyrus-registrations.md#line-of-sight.
    public var seesTarget: ((ReferenceKey, ReferenceKey) -> Bool?)?
    /// Where the player or a moving actor stands now, which its record no longer says.
    public var livePosition: ((ReferenceKey) -> SIMD3<Float>?)?

    public init() {}
}

/// Clock, conditions, packages, cell, physics, and the renderer's poses.
public struct PapyrusSessionNatives {
    /// The clock the five time globals project from, as every other `GlobalResolution` does.
    public var clockSource: (() -> GameClock?)?
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
