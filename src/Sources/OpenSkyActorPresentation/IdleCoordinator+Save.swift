// What a save keeps of the idles: the idle each actor plays and its target. A load
// plays it again on the actor (docs/engine/idle-runtime.md#what-a-save-keeps).

public import OpenSkyFormatsESM
public import OpenSkyWorldInterface

extension IdleCoordinator {
    /// The idle each actor plays or loads now, and those a save kept for an actor
    /// that is not loaded yet.
    public func savedIdlePlays() -> [ReferenceKey: SavedIdlePlay] {
        var saved = savedPlays
        for (key, session) in sessions where session.playing != nil || session.waiting != nil {
            if let play = session.savedPlay {
                saved[key] = play
            }
        }
        return saved
    }

    /// Takes the idles a save kept. Each plays once its actor is loaded.
    public func restoreIdlePlays(_ saved: [ReferenceKey: SavedIdlePlay]) {
        savedPlays = saved
    }

    /// The player has no playback; any other actor waits for its 3D.
    func replaySavedPlays(actors: [ReferenceKey: IdleActorPresence]) {
        guard !savedPlays.isEmpty else { return }
        for key in savedPlays.keys.sorted() {
            let loaded = actors[key].map { !$0.isDead && actorPlayback(key) != nil } ?? false
            guard key == .player || loaded, let play = savedPlays.removeValue(forKey: key) else {
                continue
            }
            fireIdle(play.idle, on: key, target: play.target, ignoringConditions: true)
        }
    }
}
