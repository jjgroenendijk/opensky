// `ADIA`: the social timer, the partner search, and the walk to the partner once a
// quest answers with a scene. docs/engine/random-conversations.md.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyQuestsInterface
import simd

nonisolated extension SocialEventCore {
    /// Each free speaker whose timer ran out takes the first valid partner in key order.
    /// No chance is rolled. A try with no partner rolls a new timer.
    static func conversations(
        _ frame: SocialFrame, settings: SocialSettings, elapsed: Double, state: inout SocialState
    ) -> [SocialEventCommand] {
        let actors = frame.actors
        var commands: [SocialEventCommand] = []
        for speaker in actors {
            guard speaker.isFree || speaker.isInScene else { continue }
            if !speaker.isInScene, let left = state.socialTimers[speaker.key] {
                state.socialTimers[speaker.key] = left - elapsed
            }
            guard canStart(speaker, frame: frame, state: state) else { continue }
            countDownRecent(speaker.key, elapsed: elapsed, state: &state)
            guard let left = state.socialTimers[speaker.key] else {
                state.socialTimers[speaker.key] = rollTimer(settings, &state.random)
                continue
            }
            guard left <= 0 else { continue }
            state.socialTimers[speaker.key] = rollTimer(settings, &state.random)
            let recent = state.recentPartners[speaker.key] ?? []
            let partner = actors.first { other in
                other.key != speaker.key && !recent.contains(other.key)
                    && canStart(other, frame: frame, state: state)
                    && isNear(other, speaker, frame: frame, settings: settings)
            }
            guard let partner else { continue }
            state.conversations.append(SocialConversation(
                speaker: speaker.key, partner: partner.key, startedAt: frame.now
            ))
            state.recentPartners[speaker.key, default: []].insert(partner.key)
            state.recentPartners[partner.key, default: []].insert(speaker.key)
            commands.append(.reportStoryEvent(event("ADIA", speaker.key, partner.key)))
        }
        return commands
    }

    /// Free, flag 0x02, in no conversation, and within 3000 units of the player.
    static func canStart(_ actor: SocialActor, frame: SocialFrame, state: SocialState) -> Bool {
        guard
            actor.isFree, actor.allowsConversation, !state.isBusy(actor.key),
            let player = frame.player
        else { return false }
        return simd_distance(actor.feet, player) <= SocialLimits.playerDistance
    }

    static func isNear(
        _ partner: SocialActor, _ speaker: SocialActor, frame: SocialFrame, settings: SocialSettings
    ) -> Bool {
        let radius = frame.isInterior ? settings.interiorRadius : settings.radius
        guard simd_distance(partner.feet, speaker.feet) <= radius else { return false }
        return !frame.isInterior || abs(partner.feet.z - speaker.feet.z) < SocialLimits
            .interiorHeight
    }

    /// The recent list empties every 120 s, counted only on passes that check the actor.
    static func countDownRecent(_ key: ReferenceKey, elapsed: Double, state: inout SocialState) {
        let left = (state.recentTimers[key] ?? SocialLimits.recentPartnerSeconds) - elapsed
        if left <= 0 {
            state.recentPartners[key] = nil
            state.recentTimers[key] = SocialLimits.recentPartnerSeconds
        } else {
            state.recentTimers[key] = left
        }
    }

    /// Moves each conversation on. A quest answers by putting the speaker in a scene; a
    /// pair too far apart then walks together, and the conversation ends with the scene.
    static func progress(
        _ frame: SocialFrame,
        settings: SocialSettings,
        state: inout SocialState,
        canSee: (SocialActor, SocialActor) -> Bool
    ) -> [SocialEventCommand] {
        let byKey = Dictionary(frame.actors.map { ($0.key, $0) }) { first, _ in first }
        var commands: [SocialEventCommand] = []
        var kept: [SocialConversation] = []
        for var talk in state.conversations {
            guard
                let speaker = byKey[talk.speaker], let partner = byKey[talk.partner],
                !speaker.isDead, !partner.isDead
            else {
                commands += end(talk, settings: settings, state: &state)
                continue
            }
            let inScene = speaker.isInScene || state.sceneMeetings.contains(speaker.key)
            switch talk.phase {
            case .waitingForAnswer:
                guard inScene else {
                    let waits = frame.now - talk.startedAt < talk.answerSeconds
                    commands += waits ? [] : end(talk, settings: settings, state: &state)
                    kept += waits ? [talk] : []
                    continue
                }
                let trigger = triggerDistance(speaker, partner, settings: settings, canSee: canSee)
                commands.append(.hold(partner.key))
                if simd_distance(speaker.feet, partner.feet) > trigger {
                    talk.phase = .approaching
                    if speaker.posture != .standing {
                        commands.append(.standUp(speaker.key))
                    }
                    commands += walk(&talk, speaker: speaker, partner: partner)
                } else {
                    talk.phase = .talking
                    commands += face(speaker.key, partner.key)
                }
            case .approaching:
                guard !speaker.isInCombat, inScene else {
                    commands += end(talk, settings: settings, state: &state)
                    continue
                }
                if simd_distance(speaker.feet, partner.feet) <= stopDistance(speaker, partner) {
                    talk.phase = .talking
                    commands.append(.stopWalking(speaker.key))
                    commands += face(speaker.key, partner.key)
                } else if
                    let goal = talk.goal,
                    simd_distance(goal, partner.feet) > SocialLimits.repathDistance
                {
                    commands += walk(&talk, speaker: speaker, partner: partner)
                }
            case .talking:
                guard inScene || partner.isInScene else {
                    commands += end(talk, settings: settings, state: &state)
                    continue
                }
            }
            kept.append(talk)
        }
        state.conversations = kept
        state.sceneMeetings.formIntersection(kept.map(\.speaker))
        return commands
    }

    /// `iAISocialDistanceToTriggerEvent`, raised to 500 units when the speaker sees the
    /// partner or both sit or sleep, plus 20 when the speaker sits.
    static func triggerDistance(
        _ speaker: SocialActor, _ partner: SocialActor, settings: SocialSettings,
        canSee: (SocialActor, SocialActor) -> Bool
    ) -> Float {
        let bothRest = speaker.posture != .standing && partner.posture != .standing
        let base = bothRest || canSee(speaker, partner)
            ? max(settings.triggerDistance, SocialLimits.seenTriggerDistance)
            : settings.triggerDistance
        return speaker.posture == .sitting ? base + SocialLimits.seatedTriggerAllowance : base
    }

    /// The story manager's walk for a pair's `ADIA` ended. With no quest the pair ends
    /// at once and the speaker rolls a new timer; with a quest both roll new timers.
    /// A package's request keeps its own wait.
    static func answer(
        pair: (speaker: ReferenceKey, partner: ReferenceKey), started: Bool,
        settings: SocialSettings, state: inout SocialState
    ) {
        let (speaker, partner) = pair
        guard
            let index = state.conversations.firstIndex(where: {
                $0.speaker == speaker && $0.partner == partner && $0.phase == .waitingForAnswer
            })
        else { return }
        if started {
            state.socialTimers[speaker] = rollTimer(settings, &state.random)
            state.socialTimers[partner] = rollTimer(settings, &state.random)
        } else if !state.conversations[index].isPackageRequest {
            state.conversations.remove(at: index)
            state.socialTimers[speaker] = rollTimer(settings, &state.random)
        }
    }

    /// 170 units, and 20 more when the pair's heights differ by more than 20.
    static func stopDistance(_ speaker: SocialActor, _ partner: SocialActor) -> Float {
        abs(speaker.feet.z - partner.feet.z) > SocialLimits.heightAllowance
            ? SocialLimits.stopDistance + SocialLimits.heightAllowance
            : SocialLimits.stopDistance
    }

    private static func walk(
        _ talk: inout SocialConversation, speaker: SocialActor, partner: SocialActor
    ) -> [SocialEventCommand] {
        talk.goal = partner.feet
        return [.walk(speaker.key, to: partner.feet)]
    }

    private static func face(
        _ speaker: ReferenceKey,
        _ partner: ReferenceKey
    ) -> [SocialEventCommand] {
        [.look(speaker, at: partner), .look(partner, at: speaker)]
    }

    /// Lets both go. A pair whose quest never answered rolls new timers.
    static func end(
        _ talk: SocialConversation, settings: SocialSettings, state: inout SocialState
    ) -> [SocialEventCommand] {
        switch talk.phase {
        case .waitingForAnswer:
            state.socialTimers[talk.speaker] = rollTimer(settings, &state.random)
            return []
        case .approaching:
            return [.stopWalking(talk.speaker), .release(talk.partner)]
        case .talking:
            return [
                .release(talk.partner), .look(talk.speaker, at: nil), .look(talk.partner, at: nil)
            ]
        }
    }
}
