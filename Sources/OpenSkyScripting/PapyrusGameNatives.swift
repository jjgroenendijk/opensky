// The session-wide `Game` and `Debug` natives the app answers: saving, quitting, fades,
// screen effects, the title menu, and a few actor and reference reads. As in
// `PapyrusActorNatives.swift`, a nil member is a session without that runtime.

import OpenSkyFormatsESM
import OpenSkyScriptingInterface
import simd

/// The `Game.PlayBink` arguments (<https://ck.uesp.net/wiki/PlayBink_-_Game>).
nonisolated public struct PapyrusBinkRequest: Equatable, Sendable {
    public let fileName: String
    public let interruptible: Bool
    public let muteAudio: Bool
    public let muteMusic: Bool
    public let letterbox: Bool

    public init(
        fileName: String, interruptible: Bool, muteAudio: Bool, muteMusic: Bool, letterbox: Bool
    ) {
        self.fileName = fileName
        self.interruptible = interruptible
        self.muteAudio = muteAudio
        self.muteMusic = muteMusic
        self.letterbox = letterbox
    }
}

/// A fade the `Game.FadeOutGame` arguments describe.
nonisolated public struct PapyrusFade: Equatable, Sendable {
    public let fadingOut: Bool
    /// Black when true, white when false.
    public let black: Bool
    public let secondsBeforeFade: Float
    public let duration: Float

    public init(fadingOut: Bool, black: Bool, secondsBeforeFade: Float, duration: Float) {
        self.fadingOut = fadingOut
        self.black = black
        self.secondsBeforeFade = secondsBeforeFade
        self.duration = duration
    }
}

/// `PlayImpactEffect`'s pick: from the reference, or one of its nodes, along a direction.
nonisolated public struct PapyrusImpactPick: Equatable, Sendable {
    public let source: ReferenceKey
    /// Empty picks from the reference itself.
    public let node: String
    public let direction: SIMD3<Float>
    public let length: Float
    /// The node's rotation turns `direction`: its own one, or its world one.
    public let appliesNodeRotation: Bool
    public let usesNodeLocalRotation: Bool

    public init(
        source: ReferenceKey, node: String, direction: SIMD3<Float>, length: Float,
        appliesNodeRotation: Bool, usesNodeLocalRotation: Bool
    ) {
        self.source = source
        self.node = node
        self.direction = direction
        self.length = length
        self.appliesNodeRotation = appliesNodeRotation
        self.usesNodeLocalRotation = usesNodeLocalRotation
    }
}

/// A node lookup: its world transform, missing, or waiting on the model to load.
nonisolated public enum PapyrusNodeAnswer: Equatable, Sendable {
    case found(simd_float4x4)
    case missing
    case loading(token: UInt64)
}

/// The app's answers to the session natives.
public struct PapyrusGameNatives {
    /// `RequestSave` (false) and `RequestAutoSave` (true). True when a save started.
    public var requestSave: ((_ autosave: Bool) -> Bool)?
    public var quitToMainMenu: (() -> Void)?
    public var quitGame: (() -> Void)?
    public var fade: ((PapyrusFade) -> Void)?
    /// Shows or hides the opening titles movie over the world.
    public var showTitleSequenceMenu: ((Bool) -> Void)?
    /// Plays one clip of the titles movie, such as "Sequence1".
    public var startTitleSequence: ((String) -> Void)?
    public var screenBlood: ((Int) -> Void)?
    /// Removes blood and other short-lived decals.
    public var clearTempEffects: (() -> Void)?
    /// True when the capture was written.
    public var takeScreenshot: ((String) -> Bool)?
    public var toggleCollisions: (() -> Void)?
    /// Moves the player into the named cell. False when no cell has the name.
    public var centerOnCell: ((String) -> Bool)?
    public var setGodMode: ((Bool) -> Void)?
    /// `Debug.SetFootIK`: foot IK on or off for every actor and the player.
    public var setFootIK: ((Bool) -> Void)?
    public var showFirstPersonGeometry: ((Bool) -> Void)?
    public var clearPrison: (() -> Void)?
    public var setPlayerReportsCrime: ((Bool) -> Void)?
    public var playerGrabbedReference: (() -> ReferenceKey?)?
    /// Where the actor's package would place it.
    public var packageLocation: ((ReferenceKey) -> SIMD3<Float>?)?
    /// Removes the arrows stuck in an actor. Returns how many.
    public var clearExtraArrows: ((ReferenceKey) -> Int)?
    /// Plays an impact data set where the pick from a reference meets a surface.
    /// False when it cannot play.
    public var playImpact: ((_ impacts: ReferenceKey, PapyrusImpactPick) -> Bool)?
    /// Turns a dead actor into a ragdoll now. False when it has none.
    public var forceRagdoll: ((ReferenceKey) -> Bool)?
    /// A named node of a reference's 3D, as a world transform. A model still loading
    /// answers later: the app runs `then` with the transform and answers the token.
    public var nodeTransform: (
        (ReferenceKey, String, _ then: @escaping (simd_float4x4?) -> PapyrusValue)
            -> PapyrusNodeAnswer
    )?
    /// `Sound.Play` from a reference: the instance ID, 0 when it cannot play. A
    /// `waitToken` is answered with whether the sound played to its end.
    public var playSound: (
        (_ sound: ReferenceKey, _ source: ReferenceKey, _ waitToken: UInt64?) -> Int32
    )?
    public var stopSound: ((Int32) -> Void)?
    /// Lays an `SPGD` over the weather, or removes it for nil, over the seconds given.
    public var setParticleGeometry: ((_ geometry: ReferenceKey?, _ seconds: Float) -> Void)?
    public var setSoundVolume: ((Int32, Float) -> Void)?
    /// `Actor.PathToReference`: starts the walk and answers `waitToken` with whether
    /// the actor arrived. False when no path starts.
    public var pathToReference: (
        (_ actor: ReferenceKey, _ target: ReferenceKey, _ speed: Float, _ waitToken: UInt64)
            -> Bool
    )?
    /// `Game.PlayBink`: starts the movie and answers `waitToken` once it ends. False when
    /// it cannot start.
    public var playBink: ((PapyrusBinkRequest, _ waitToken: UInt64) -> Bool)?
    /// Resets a cell the next time it loads. False when the cell is unknown.
    public var resetCell: ((ReferenceKey) -> Bool)?

    public init() {}
}
