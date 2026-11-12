// An idle whose clip leads on to more clips, such as a furniture enter clip that
// leads to the seat's idle loop: each clip plays in turn, and the last one holds
// when it loops. See docs/engine/idle-runtime.md.

import OpenSkyBehavior
import OpenSkyFormatsAnimation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldInterface

extension IdleCoordinator {
    /// An idle's clips in order, and whether the last one holds.
    struct Chain {
        let first: Segment
        let followUps: [Segment]
        let holdsLast: Bool
    }

    /// Starts the next clip of the chain where the last one ended.
    func nextSegment(after playing: Playing, on actor: ReferenceKey) -> Playing? {
        guard let segment = playing.followUps.first else { return nil }
        let followUps = Array(playing.followUps.dropFirst())
        let start = playing.end
        let duration = segment.duration
        let held = followUps.isEmpty && playing.holdsLast
        let seconds = held ? Float.infinity : duration
        let playback = actorPlayback(actor)
        if !playing.throughGraph {
            playback?.play(segment.clip, startingAt: start, forSeconds: seconds)
        }
        let marks = segment.marks
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
            animationObjects: playing.animationObjects, shownObject: playing.shownObject,
            throughGraph: playing.throughGraph
        )
    }
}

extension IdleCoordinator.Segment {
    static func isLoading(_ state: AssetLoadState<ActorAnimationClip>?) -> Bool {
        if case .loading = state {
            return true
        }
        return false
    }

    /// The follow-up clips that loaded, in plan order.
    static func loaded(of plan: IdlePlaybackPlan, clips: [ActorAnimationClip?]) -> [Self] {
        zip(plan.followUps, clips).compactMap { segment, clip in
            clip.map { Self(clip: $0, triggers: segment.triggers) }
        }
    }

    var duration: Float {
        clip.animation.duration
    }

    var marks: [IdleAnimationEvent] {
        IdleCore.clipMarks(
            annotations: clip.animation.annotations,
            triggers: triggers,
            clipDuration: clip.animation.duration
        )
    }
}

extension ActorClipLoader {
    /// The player has no playback, so a player idle only times its events with this rig.
    static var playerSkeletonPath: String {
        ActorAnimationClipLoader.characterRoot + "character assets\\skeleton.nif"
    }

    /// True while a clip of `plan` still loads for `skeleton`.
    func isLoading(_ plan: IdlePlaybackPlan, skeleton: String) -> Bool {
        states(of: plan, skeleton: skeleton).contains(where: IdleCoordinator.Segment.isLoading)
    }

    /// The plan's clips that loaded, in order; nil when the first one did not load.
    func chain(
        of plan: IdlePlaybackPlan, skeleton: String, holds: Bool
    ) -> IdleCoordinator.Chain? {
        let states = states(of: plan, skeleton: skeleton)
        guard let first = states.first??.value else { return nil }
        return IdleCoordinator.Chain(
            first: IdleCoordinator.Segment(clip: first, triggers: plan.triggers),
            followUps: IdleCoordinator.Segment.loaded(
                of: plan, clips: states.dropFirst().map { $0?.value }
            ),
            holdsLast: holds
        )
    }

    private func states(
        of plan: IdlePlaybackPlan, skeleton: String
    ) -> [AssetLoadState<ActorAnimationClip>?] {
        plan.clipPaths.map {
            state(of: ActorClipKey(skeletonMeshPath: skeleton, animationPath: $0))
        }
    }
}
