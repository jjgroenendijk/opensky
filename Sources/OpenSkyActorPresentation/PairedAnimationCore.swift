// Which two actors play a paired animation, such as a kill move or a feed, and when the
// pair ends. Pure rules; `IdleCoordinator+Paired.swift` runs them.
// See docs/engine/paired-animations.md.

import Foundation
import OpenSkyBehavior
import OpenSkyFormatsESM

/// One paired animation in progress.
nonisolated public struct PairedAnimationPlay: Equatable, Sendable {
    /// The actor that started it, such as the killer.
    public let lead: ReferenceKey
    /// The other actor, such as the victim.
    public let partner: ReferenceKey
    /// The `IDLE` that started it, by editor ID.
    public let idle: String
    /// The `IDLE`'s event, which the lead's graph got.
    public let event: String
    public let start: Float
    /// False when the partner's graph did not take the event, so only the lead plays.
    public internal(set) var partnerTookEvent = true
    /// Where the partner stood when the pair started; it moves from here to the mark.
    public internal(set) var partnerStart: PairedActorPose?
    /// True once the partner stands on the mark.
    public internal(set) var isAtMark = false
    /// True once an update ran without the partner's graph showing a synchronized clip.
    var waitedForMark = false

    public init(
        lead: ReferenceKey, partner: ReferenceKey, idle: String, event: String, start: Float
    ) {
        self.lead = lead
        self.partner = partner
        self.idle = idle
        self.event = event
        self.start = start
    }

    public func involves(_ actor: ReferenceKey) -> Bool {
        lead == actor || partner == actor
    }

    /// The kill-move idles all send `pa_KillMove...`. [WARNING] OpenSky's reading of the
    /// event names; `IsInKillMove` reads it.
    public var isKillMove: Bool {
        event.lowercased().hasPrefix(PairedAnimationCore.pairedEventPrefix + "killmove")
    }
}

nonisolated public enum PairedAnimationCore {
    /// Every vanilla `IDLE` whose event plays a synchronized clip on two actors starts
    /// with this, such as `pa_KillMoveC` and `pa_VampireFeedStanding_Front`.
    public static let pairedEventPrefix = "pa_"
    /// The clips send these as the pair ends: `PairEnd` on the kill moves, `pairedStop` on
    /// the mount, `PairedStop` on the werewolf and vampire lord clips.
    public static let endEvents = ["PairEnd", "pairedStop"]
    /// A pair whose end event never comes ends after this long. [WARNING] OpenSky's choice:
    /// the longest vanilla paired clip found is shorter.
    public static let maximumSeconds: Float = 30

    /// True when an `IDLE` with this event plays on two actors.
    public static func isPaired(event: String) -> Bool {
        event.lowercased().hasPrefix(pairedEventPrefix)
    }

    /// The partner's graph takes the lead's event with `pa_` toggled: `pa_KillMoveC` leads
    /// the victim to `NPC_KillMoveC` as `KillMoveC`, and the rider's `HorseEnter` the horse
    /// as `pa_HorseEnter`. Read from the install's graphs.
    public static func partnerEvent(of event: String) -> String {
        isPaired(event: event) ? String(event.dropFirst(pairedEventPrefix.count))
            : pairedEventPrefix + event
    }

    /// The lead's half of a synchronized clip sends its own events as `NPC` and the name,
    /// such as `NPCSoundPlay.NPCKillMelee`; the partner's half as `2_` and the name, such
    /// as `2_KillActor`. Read from the install's graphs.
    public static let eventPrefixes = ["2_", "NPC"]

    /// The event a paired actor's graph means, without its half's prefix, or nil.
    public static func ownEvent(_ name: String) -> String? {
        for prefix in eventPrefixes where name.count > prefix.count && name.hasPrefix(prefix) {
            return String(name.dropFirst(prefix.count))
        }
        return nil
    }

    /// True when a graph event of either actor ends the pair.
    public static func ends(onEvent name: String) -> Bool {
        endEvents.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
    }

    public static func hasExpired(_ play: PairedAnimationPlay, now: Float) -> Bool {
        now - play.start >= maximumSeconds || now < play.start
    }
}

/// Where one actor of a pair stands: its feet, and its heading in radians about z.
nonisolated public struct PairedActorPose: Equatable, Sendable {
    public let feet: SIMD3<Float>
    public let heading: Float

    public init(feet: SIMD3<Float>, heading: Float) {
        self.feet = feet
        self.heading = heading
    }
}

nonisolated extension PairedAnimationCore {
    /// The partner `seconds` after the pair started, on its way from `start` to `mark`.
    /// The move is linear in time (docs/engine/paired-animations.md#reaching-the-mark).
    public static func approach(
        from start: PairedActorPose, to mark: PairedActorPose, after seconds: Float,
        _ synchronized: BehaviorSynchronizedMark
    ) -> PairedActorPose {
        guard synchronized.reorientsSupportCharacter else {
            return PairedActorPose(feet: mark.feet, heading: start.heading)
        }
        let time = synchronized.getToMarkTime
        let progress = time > 0 && seconds.isFinite ? min(max(seconds / time, 0), 1) : 1
        let turn = remainder(mark.heading - start.heading, 2 * Float.pi)
        return PairedActorPose(
            feet: start.feet + (mark.feet - start.feet) * progress,
            heading: progress >= 1 ? mark.heading : start.heading + turn * progress
        )
    }

    public static func reachesMark(after seconds: Float, _ synchronized: BehaviorSynchronizedMark)
        -> Bool
    {
        !synchronized.reorientsSupportCharacter || seconds >= synchronized.getToMarkTime
    }
}
