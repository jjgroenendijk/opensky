// Paired idles: one `IDLE` starts two actors' graphs, each on its own half of one
// synchronized clip. See docs/engine/paired-animations.md.

import OpenSkyBehavior
public import OpenSkyFormatsESM

extension IdleCoordinator {
    /// The `source` of the report a paired idle leaves.
    public static let pairedSource = "paired"

    /// The lead's graph takes the idle's event and the partner's graph the partner event.
    /// Each state reads its own half of the clip, so the partner then moves to the lead's
    /// root, where both halves meet.
    @discardableResult
    func firePaired(_ play: PairedAnimationPlay, trace: [IdleCandidateTrace]) -> IdleReport {
        let (lead, partner) = (play.lead, play.partner)
        endPairs(involving: lead)
        endPairs(involving: partner)
        guard world?.raiseIdleEvent(play.event, state: nil, on: lead) == true else {
            return record(IdleReport(
                actor: lead, source: Self.pairedSource, trace: trace, chosen: play.idle,
                plan: nil, seconds: 0, failure: "the lead's graph did not take \(play.event)"
            ))
        }
        let partnerEvent = PairedAnimationCore.partnerEvent(of: play.event)
        var started = play
        started.partnerStart = world?.pairedActorPose(of: partner)
        started.partnerTookEvent = world?.raiseIdleEvent(partnerEvent, state: nil, on: partner)
            == true
        pairs.append(started)
        return record(IdleReport(
            actor: lead, source: Self.pairedSource, trace: trace, chosen: play.idle, plan: nil,
            seconds: PairedAnimationCore.maximumSeconds,
            failure: started.partnerTookEvent
                ? nil : "the partner's graph did not take \(partnerEvent)"
        ))
    }

    /// The pair `actor` plays a half of, or nil.
    public func pairedAnimation(of actor: ReferenceKey) -> PairedAnimationPlay? {
        pairs.first { $0.involves(actor) }
    }

    /// What a graph event means: while the actor plays a half of a pair, its half's
    /// prefix comes off. The pair ends when either half sends the clip's end event.
    public func ownGraphEvent(_ name: String, from actor: ReferenceKey) -> String {
        guard pairedAnimation(of: actor) != nil else { return name }
        let own = PairedAnimationCore.ownEvent(name) ?? name
        if PairedAnimationCore.ends(onEvent: own) {
            endPairs(involving: actor)
        }
        return own
    }

    /// Moves each partner toward its mark. A partner whose graph shows no synchronized
    /// clip one update after the start stands on the mark at once.
    func approachMarks(now: Float) {
        for index in pairs.indices where !pairs[index].isAtMark {
            let play = pairs[index]
            guard
                let world, let start = play.partnerStart,
                let mark = world.pairedActorPose(of: play.lead)
            else { continue }
            let synchronized = world.synchronizedMark(of: play.partner)
            if synchronized == nil, !play.waitedForMark, play.partnerTookEvent {
                pairs[index].waitedForMark = true
                continue
            }
            let rule = synchronized
                ?? BehaviorSynchronizedMark(getToMarkTime: 0, reorientsSupportCharacter: true)
            let seconds = now - play.start
            world.placePairedActor(
                play.partner,
                at: PairedAnimationCore.approach(from: start, to: mark, after: seconds, rule)
            )
            pairs[index].isAtMark = PairedAnimationCore.reachesMark(after: seconds, rule)
        }
    }

    func expirePairs(now: Float) {
        for play in pairs where PairedAnimationCore.hasExpired(play, now: now) {
            endPairs(involving: play.lead)
        }
    }

    func endPairs(involving actor: ReferenceKey) {
        pairs.removeAll { $0.involves(actor) }
    }
}
