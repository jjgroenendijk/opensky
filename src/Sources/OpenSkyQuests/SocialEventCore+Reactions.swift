// Reactions to what an actor detects: a dead body (`DEAD` and a `NoticeCorpse` line)
// and a fight to watch (`ObserveCombat` lines). docs/engine/random-conversations.md.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyQuestsInterface
import simd

nonisolated extension SocialEventCore {
    /// A free finder with flag 0x08 sees a body within 400 units that no actor checked
    /// in the last 20 s. One finder per body; it leaves any conversation it is in.
    static func bodies(
        _ frame: SocialFrame,
        settings: SocialSettings,
        state: inout SocialState,
        canSee: (SocialActor, SocialActor) -> Bool
    ) -> [SocialEventCommand] {
        let actors = frame.actors
        let now = frame.now
        let bodies = actors.filter(\.isDead)
        guard !bodies.isEmpty else { return [] }
        var commands: [SocialEventCommand] = []
        for finder in actors where finder.isFree && finder.greetsCorpses {
            let body = bodies.first { body in
                now - (state.bodyChecks[body.key] ?? -.infinity) >= SocialLimits.bodySeconds
                    && simd_distance(finder.feet, body.feet) <= SocialLimits.bodyDistance
                    && canSee(finder, body)
            }
            guard let body else { continue }
            state.bodyChecks[body.key] = now
            if let talk = state.conversation(of: finder.key) {
                state.conversations.removeAll { $0 == talk }
                commands += end(talk, settings: settings, state: &state)
            }
            commands.append(.reportStoryEvent(event("DEAD", finder.key, body.key)))
            commands.append(.say("NOTI", finder.key, lookAt: body.key))
        }
        return commands
    }

    /// Starts, keeps, and ends each watch, and rolls the comments.
    static func spectators(
        _ frame: SocialFrame,
        settings: SocialSettings,
        state: inout SocialState,
        canSee: (SocialActor, SocialActor) -> Bool
    ) -> [SocialEventCommand] {
        let actors = frame.actors
        let pass = WatchPass(
            byKey: Dictionary(actors.map { ($0.key, $0) }) { first, _ in first },
            now: frame.now, settings: settings
        )
        var commands: [SocialEventCommand] = []
        for (key, watch) in state.spectators.sorted(by: { $0.key < $1.key }) {
            commands += keepWatching(key, watch, pass: pass, state: &state)
        }
        for watcher in actors where state.spectators[watcher.key] == nil && canWatch(
            watcher,
            state: state
        ) {
            let fighter = actors.first { fighter in
                fighter.key != .player && !fighter.isDead && fighter.isInCombat
                    && fighter.combatTarget != watcher.key
                    && simd_distance(fighter.feet, watcher.feet) <= SocialLimits.watchDistance
                    && canSee(watcher, fighter)
            }
            guard let fighter else { continue }
            state.spectators[watcher.key] = SocialSpectator(
                fighter: fighter.key, lastSeenFighting: frame.now, inScene: watcher.isInScene
            )
            if !watcher.isInScene {
                commands += [.hold(watcher.key), .look(watcher.key, at: fighter.key)]
            }
        }
        return commands
    }

    /// Alive, not the player, not fighting or fled, flag 0x04, and in no conversation. A
    /// watcher in a scene keeps its scene and only reports that it watches.
    static func canWatch(_ actor: SocialActor, state: SocialState) -> Bool {
        !actor.isDead && actor.key != .player && !actor.isInCombat && actor.combatTarget == nil
            && actor.observesCombat && state.conversation(of: actor.key) == nil
    }

    /// What every watch in one pass reads.
    private struct WatchPass {
        let byKey: [ReferenceKey: SocialActor]
        let now: Double
        let settings: SocialSettings
    }

    private static func keepWatching(
        _ key: ReferenceKey, _ watch: SocialSpectator, pass: WatchPass, state: inout SocialState
    ) -> [SocialEventCommand] {
        let byKey = pass.byKey
        let settings = pass.settings
        var watch = watch
        guard
            let watcher = byKey[key], let fighter = byKey[watch.fighter],
            !watcher.isDead, !watcher.isInCombat, !fighter.isDead,
            simd_distance(watcher.feet, fighter.feet) <= SocialLimits.watchDistance
        else { return stopWatching(key, watch, state: &state) }
        if fighter.isInCombat {
            watch.lastSeenFighting = pass.now
        } else if pass.now - watch.lastSeenFighting > Double(settings.spectatorRememberSeconds) {
            return stopWatching(key, watch, state: &state)
        }
        var commands: [SocialEventCommand] = []
        let rested = watch.lastComment.map { pass.now - $0 >= SocialLimits.commentSeconds } ?? true
        if
            rested,
            Float(state.random.next() % UInt64(10000)) / Float(100) < settings.observeCombatChance
        {
            watch.lastComment = pass.now
            commands.append(.say("OBCO", key, lookAt: watch.fighter))
        }
        state.spectators[key] = watch
        return commands
    }

    private static func stopWatching(
        _ key: ReferenceKey, _ watch: SocialSpectator, state: inout SocialState
    ) -> [SocialEventCommand] {
        state.spectators[key] = nil
        return watch.inScene ? [] : [.release(key), .look(key, at: nil)]
    }
}
