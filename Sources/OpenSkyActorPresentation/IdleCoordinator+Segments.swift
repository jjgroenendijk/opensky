// An idle whose clip leads on to more clips, such as a furniture enter clip that
// leads to the seat's idle loop: each clip plays in turn, and the last one holds
// when it loops. See docs/engine/idle-runtime.md.

import OpenSkyBehavior
import OpenSkyFormatsAnimation
import OpenSkyFormatsESM
import OpenSkyGameData

extension IdleCoordinator {
    /// An idle's clips in order, and whether the last one holds.
    struct Chain {
        let first: Segment
        let followUps: [Segment]
        let holdsLast: Bool
    }

    static func isLoading(_ state: AssetLoadState<ActorAnimationClip>?) -> Bool {
        if case .loading = state {
            return true
        }
        return false
    }

    /// The follow-up clips that loaded, in plan order.
    static func segments(of plan: IdlePlaybackPlan, clips: [ActorAnimationClip?]) -> [Segment] {
        zip(plan.followUps, clips).compactMap { segment, clip in
            clip.map { Segment(clip: $0, triggers: segment.triggers) }
        }
    }

    static func marks(of segment: Segment) -> [IdleAnimationEvent] {
        IdleCore.clipMarks(
            annotations: segment.clip.animation.annotations,
            triggers: segment.triggers,
            clipDuration: segment.clip.animation.duration
        )
    }

    /// Starts the next clip of the chain where the last one ended.
    func nextSegment(after playing: Playing, on actor: ReferenceKey) -> Playing? {
        guard let segment = playing.followUps.first else { return nil }
        let followUps = Array(playing.followUps.dropFirst())
        let start = playing.end
        let duration = segment.clip.animation.duration
        let held = followUps.isEmpty && playing.holdsLast
        let seconds = held ? Float.infinity : duration
        let playback = world?.actorPlayback(for: actor)
        playback?.play(segment.clip, startingAt: start, forSeconds: seconds)
        let marks = Self.marks(of: segment)
        let exit = followUps.isEmpty && !held ? playing.exitEvents : []
        let events = IdleCore.playEvents(
            marks: marks, notify: BehaviorStateNotify(exit: exit),
            clipDuration: duration, seconds: duration
        ).map { IdleAnimationEvent(time: start + $0.time, name: $0.name) }
        return Playing(
            clip: segment.clip, start: start, end: start + seconds, hasProp: playing.hasProp,
            exitEvents: playing.exitEvents, loopEnd: held && duration > 0 ? start + duration : nil,
            playback: playback.map(ObjectIdentifier.init), events: playing.events + events,
            marks: marks, followUps: followUps, holdsLast: playing.holdsLast,
            animationObjects: playing.animationObjects, shownObject: playing.shownObject
        )
    }
}
