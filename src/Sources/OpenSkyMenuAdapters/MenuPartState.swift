public import Foundation
public import OpenSkyAgentControl
public import OpenSkyFormatsESM
public import OpenSkyLaunch
public import OpenSkyMenus

/// What the parts of `MenuWorldAdapter` share between frames.
@MainActor
public final class MenuPartState {
    /// Set by the session scope, because quitting is the app shell's work.
    public var terminateApp: () -> Void = {}
    /// Set by the session scope, which owns the game view that reads the keys.
    public var applyViewBindings: (InputBindings) -> Void = { _ in }
    var perkSky: PerkSkySource?
    /// The move a new game makes, polled each frame until the player stands.
    public var newGameTeleport: AgentWait?
    /// A chosen test cell opens the race menu when the move ends; a quest's move does not.
    public var raceMenuAfterTeleport = false
    /// What a new game at a chosen place still changes when the move ends.
    public var arrivalSteps: [AgentDebugCommand] = []
    /// The last new game started at a chosen place.
    public var lastNewGame: LaunchNewGame?
    /// The player's race before a script or a magic effect changed it. Not saved.
    public var originalPlayerRace: FormID?
    var startTickerInstalled = false
    /// The opening quest's player `MoveTo` loads a far cell, so it gets a loading screen.
    public var coverNextTeleport = false
    public var teleportCovered = false
    /// From New until the opening quest moves the player. A dark cover, not the
    /// loading menu, because that menu pauses the scripts that make the move. On the
    /// simulation clock, so a game paused by agent control does not run out the limit.
    public var newGameCoverSince: Double?
    /// The wall clock the loading cover times itself by.
    public let now: () -> Date

    public init(now: @escaping () -> Date) {
        self.now = now
    }
}
