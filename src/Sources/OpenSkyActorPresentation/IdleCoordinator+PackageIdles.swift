// A package's own idle list (`IDLA`): an actor that stands still in its package plays
// from it, as at a marker. A scene's package action plays its idles this way.

import OpenSkyFormatsESM
import OpenSkyGameData

extension IdleCoordinator {
    /// Gives each still actor without a marker its package's list, and takes the list
    /// away when the actor walks or changes package. A playing idle finishes first.
    func updatePackageIdles(actors: [ReferenceKey: IdleActorPresence]) {
        for (key, session) in sessions where actors[key] == nil && session.packageList != nil {
            sessions[key] = session.marker == nil ? nil : session
        }
        for key in actors.keys.sorted() {
            guard let actor = actors[key] else { continue }
            let list = actor.isStill && !actor.isDead && furnitureUses[key] == nil
                ? actor.packageIdles.flatMap { $0.idles.isEmpty ? nil : $0 } : nil
            var session = sessions[key] ?? Session()
            guard session.marker == nil, session.packageList != list?.package else { continue }
            session.packageList = list?.package
            session.nextEntry = 0
            session.played = []
            session.reselectAt = 0
            let isEmpty = list == nil && session.playing == nil && session.waiting == nil
            sessions[key] = isEmpty ? nil : session
        }
    }

    func selectPackageIdle(for actor: IdleActorPresence, now: Float) {
        guard let store, let list = actor.packageIdles, var session = sessions[actor.key] else {
            return
        }
        let selection = selector(for: actor.key).select(
            entries: list.idles.compactMap { store.idles.record($0) },
            order: list.order,
            startIndex: session.nextEntry,
            played: list.isDoOnce ? session.played : [],
            random: random
        )
        if let entry = selection.chosenEntry {
            session.nextEntry = entry + 1
        }
        if let chosen = selection.chosen {
            session.played.insert(chosen.id)
        }
        // Nothing passed: look again after the timer, not every frame.
        session.reselectAt = IdleCore.nextSelection(after: now, playSeconds: 0, timer: list.timer)
        sessions[actor.key] = session
        guard selection.chosen != nil else { return }
        play(selection, on: actor.key, source: "package", timer: list.timer, now: now)
    }
}
