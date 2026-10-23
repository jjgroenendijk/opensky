// The package side of a bump: a reacting actor is held out of its package and picks it
// again when the reaction ends (docs/engine/bump-reactions.md).

import OpenSkyFormatsESM

extension PackageCoordinator {
    /// Starts reactions for this frame's contacts and moves the running ones on. A
    /// reacting actor is suspended; the app speaks and moves for the returned commands.
    public func advanceBumps(_ contacts: [BumpContact], now: Double) -> [BumpCommand] {
        let started = bumps.note(contacts, now: now, settings: bumpSettings)
        for case let .speak(actor) in started {
            suspend(actor)
        }
        let (moves, finished) = bumps.advance(now: now, settings: bumpSettings)
        for actor in finished {
            resume(actor)
        }
        return started + moves
    }
}
