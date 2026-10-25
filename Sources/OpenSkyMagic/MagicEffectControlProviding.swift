// The active-effect readout's seam: consume, dispel and coverage, without
// `GameViewController`. One snapshot value, so the readout comes from a single observation.

import Foundation
import OpenSkyMagicInterface

/// One active effect as a readout spells it.
nonisolated public struct ActiveEffectReadout: Equatable, Sendable {
    /// FULL name of the MGEF when the index resolves one, else its editor ID,
    /// else its key. Never empty, so a line always names something.
    public let name: String
    /// Where it came from, spelled for a reader: "potion", "ingredient".
    public let sourceName: String
    /// Which of the two documented timed behaviours it follows.
    public let mode: ActiveEffectMode
    public let isDetrimental: Bool
    public let magnitude: Float
    public let duration: Float
    public let remaining: Float
    /// Vanilla names of the actor values it acts on, in the MGEF's order.
    public let valueNames: [String]
    /// The MGEF archetype, spelled as xEdit spells it: "calm", "cloak".
    public let archetype: String
    /// The time left in the effects list's units, such as "2 mins".
    public var timeLeftText = ""

    /// One line, the shape the readout joins with newlines. An archetype that
    /// acts on no actor value names itself instead.
    public var line: String {
        guard !valueNames.isEmpty else {
            return String(
                format: "%@ (%@) %@ at magnitude %.1f, %.1fs of %.1fs left%@",
                name, sourceName, archetype, magnitude, remaining, duration, timeLeftSuffix
            )
        }
        let direction = isDetrimental ? "damages" : "restores"
        let behaviour = mode == .modifier ? "held" : "per second"
        let values = valueNames.joined(separator: ", ")
        return String(
            format: "%@ (%@) %@ %@ by %.1f %@, %.1fs of %.1fs left%@",
            name, sourceName, direction, values, magnitude, behaviour, remaining, duration,
            timeLeftSuffix
        )
    }

    private var timeLeftSuffix: String {
        timeLeftText.isEmpty ? "" : " (\(timeLeftText))"
    }

    public init(
        name: String,
        sourceName: String,
        mode: ActiveEffectMode,
        isDetrimental: Bool,
        magnitude: Float,
        duration: Float,
        remaining: Float,
        valueNames: [String],
        archetype: String = ""
    ) {
        self.name = name
        self.sourceName = sourceName
        self.mode = mode
        self.isDetrimental = isDetrimental
        self.magnitude = magnitude
        self.duration = duration
        self.remaining = remaining
        self.valueNames = valueNames
        self.archetype = archetype
    }
}

/// One observation of the active-effect runtime.
nonisolated public struct MagicEffectControlSnapshot: Equatable, Sendable {
    /// False when no active-effect runtime is attached — no game data, or a
    /// synthetic scene. Every other field is then empty and the readout says so
    /// rather than showing a convincing zero.
    public let isAvailable: Bool
    /// Every effect currently acting on the player, in application order.
    public let playerEffects: [ActiveEffectReadout]
    /// The nearest resident actor, or nil. The same actor as
    /// `ActorValueControlSnapshot.nearestActor`, so effects and resistances match.
    public let nearestActorName: String?
    /// What the player's effects force on the player, such as paralysis.
    public var playerInfluence = ActorMagicInfluence.none
    /// What the nearest actor's effects force on it, such as fear.
    public var nearestActorInfluence = ActorMagicInfluence.none

    /// The reading with no runtime attached.
    public static let unavailable = MagicEffectControlSnapshot(
        isAvailable: false,
        playerEffects: [],
        nearestActorName: nil
    )

    public init(
        isAvailable: Bool,
        playerEffects: [ActiveEffectReadout],
        nearestActorName: String?
    ) {
        self.isAvailable = isAvailable
        self.playerEffects = playerEffects
        self.nearestActorName = nearestActorName
    }
}
