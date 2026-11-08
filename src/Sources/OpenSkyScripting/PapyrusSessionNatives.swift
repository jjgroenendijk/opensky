// The player, perception, and session families of the Papyrus world bridge. As in
// `PapyrusActorNatives.swift`, a nil member is a session without that runtime.

import OpenSkyConditions
public import OpenSkyFormatsESM
public import OpenSkyPerceptionInterface
import OpenSkyScriptingInterface
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
