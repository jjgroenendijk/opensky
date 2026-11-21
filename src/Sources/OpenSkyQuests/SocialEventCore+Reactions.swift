// Reactions to what an actor detects: a dead body (`DEAD`, a walk to it, and a
// `NoticeCorpse` line). docs/engine/random-conversations.md#finding-a-body-dead.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyQuestsInterface
import simd

nonisolated extension SocialEventCore {
    /// A free finder with flag 0x08 sees a body within 400 units that no actor checked
    /// in the last 20 s. One finder per body; it leaves any conversation it is in and
    /// walks to the body.
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
        for finder in actors
            where finder.isFree && finder.greetsCorpses && state.finders[finder.key] == nil
            && state.spectators[finder.key] == nil
        {
            let body = bodies.first { body in
                now - (state.bodyChecks[body.key] ?? -.infinity) >= SocialLimits.bodySeconds
                    && simd_distance(finder.feet, body.feet) <= SocialLimits.bodyDistance
                    && canSee(finder, body)
            }
            guard let body else { continue }
            state.bodyChecks[body.key] = now
            commands += leaveConversation(finder.key, settings: settings, state: &state)
            commands.append(.reportStoryEvent(event("DEAD", finder.key, body.key)))
            state.finders[finder.key] = SocialFinder(body: body.key, startedAt: now)
            if finder.posture != .standing {
                commands.append(.standUp(finder.key))
            }
            if simd_distance(finder.feet, body.feet) > SocialLimits.bodyArriveDistance {
                commands.append(.walk(finder.key, to: body.feet))
            }
        }
        return commands
    }

    /// Ends the walk of each finder that reached its body or gave up. Within 400 units
    /// it says its line, unless the body remembers it.
    static func finders(_ frame: SocialFrame, state: inout SocialState) -> [SocialEventCommand] {
        guard !state.finders.isEmpty else { return [] }
        let byKey = Dictionary(frame.actors.map { ($0.key, $0) }) { first, _ in first }
        var commands: [SocialEventCommand] = []
        for (key, find) in state.finders.sorted(by: { $0.key < $1.key }) {
            guard
                let finder = byKey[key], let body = byKey[find.body],
                !finder.isDead, !finder.isInCombat
            else {
                state.finders[key] = nil
                commands.append(.stopWalking(key))
                continue
            }
            let distance = simd_distance(finder.feet, body.feet)
            let gaveUp = frame.now - find.startedAt >= SocialLimits.finderWalkSeconds
            guard distance <= SocialLimits.bodyArriveDistance || gaveUp else { continue }
            state.finders[key] = nil
            commands.append(.stopWalking(key))
            if distance <= SocialLimits.bodyDistance, state.bodyKillers[find.body] != key {
                commands.append(.say("NOTI", key, lookAt: find.body))
            }
        }
        return commands
    }

    /// Ends the conversation `actor` is in, if any.
    static func leaveConversation(
        _ actor: ReferenceKey, settings: SocialSettings, state: inout SocialState
    ) -> [SocialEventCommand] {
        guard let talk = state.conversation(of: actor) else { return [] }
        state.conversations.removeAll { $0 == talk }
        return end(talk, settings: settings, state: &state)
    }
}
