// The session-wide `Game` and `Debug` natives the app answers: saving, quitting, fades,
// screen effects, the title menu, and a few actor and reference reads. As in
// `PapyrusActorNatives.swift`, a nil member is a session without that runtime.

import OpenSkyFormatsESM
import OpenSkyScriptingInterface
import simd

/// A fade the `Game.FadeOutGame` arguments describe.
nonisolated public struct PapyrusFade: Equatable, Sendable {
    public let fadingOut: Bool
    public let black: Bool
    public let delay: Float
    public let duration: Float

    public init(fadingOut: Bool, black: Bool, delay: Float, duration: Float) {
        self.fadingOut = fadingOut
        self.black = black
        self.delay = delay
        self.duration = duration
    }
}

/// A node lookup: found, missing, or waiting on the model to load.
nonisolated public enum PapyrusNodeAnswer: Equatable, Sendable {
    case found(SIMD3<Float>)
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
    /// Shows or hides the title menu's backdrop.
    public var showTitleSequenceMenu: ((Bool) -> Void)?
    public var screenBlood: ((Int) -> Void)?
    /// Removes blood and other short-lived decals.
    public var clearTempEffects: (() -> Void)?
    /// True when the capture was written.
    public var takeScreenshot: ((String) -> Bool)?
    public var toggleCollisions: (() -> Void)?
    /// Moves the player into the named cell. False when no cell has the name.
    public var centerOnCell: ((String) -> Bool)?
    public var setGodMode: ((Bool) -> Void)?
    public var showFirstPersonGeometry: ((Bool) -> Void)?
    public var clearPrison: (() -> Void)?
    public var setPlayerReportsCrime: ((Bool) -> Void)?
    public var playerGrabbedReference: (() -> ReferenceKey?)?
    /// Where the actor's package would place it.
    public var packageLocation: ((ReferenceKey) -> SIMD3<Float>?)?
    /// Removes the arrows stuck in an actor. Returns how many.
    public var clearExtraArrows: ((ReferenceKey) -> Int)?
    /// Plays an impact data set at a reference. False when it cannot play.
    public var playImpact: ((_ impacts: ReferenceKey, _ at: ReferenceKey) -> Bool)?
    /// Turns a dead actor into a ragdoll now. False when it has none.
    public var forceRagdoll: ((ReferenceKey) -> Bool)?
    /// A named node of a reference's model, in world space. A model still loading
    /// answers later: the app runs `then` with the position and answers the token.
    public var nodePosition: (
        (ReferenceKey, String, _ then: @escaping (SIMD3<Float>?) -> PapyrusValue)
            -> PapyrusNodeAnswer
    )?
    /// Resets a cell the next time it loads. False when the cell is unknown.
    public var resetCell: ((ReferenceKey) -> Bool)?

    public init() {}
}
