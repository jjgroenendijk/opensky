// What an actor's values are before anything at runtime touched them. Never
// stored: re-derived from plugin data on every call, so a reset restores what
// the records say now. See docs/engine/actor-values.md.

import Foundation
import OpenSkyFormatsESM

/// Which plugin record an actor's baseline comes from.
///
/// A `ReferenceKey` alone cannot answer this — the store keys state by identity
/// and knows nothing about record types — so the caller holding the placement
/// says which kind of subject it has. The shape mirrors `InventoryOwner`
/// deliberately: the two travel together at every call site that has an ACHR.
nonisolated public enum ActorValueSubject: Equatable, Sendable {
    /// The player. No record in this engine describes the player
    /// (`ReferenceKey.player`), so its baseline comes from the configured
    /// player race rather than from an NPC_.
    case player
    /// A placed ACHR, identified by its NPC_ base record.
    case actor(base: FormID)
    /// An actor with no plugin baseline — a summon a later milestone creates.
    case generated
}

/// One subject's identity, its baseline source, and the cell its mutations are
/// attributed to.
///
/// The three travel together for the same reason `InventoryHolder`'s do: every
/// mutation needs all three, and passing them separately is how a mutation ends
/// up attributed to the wrong cell.
nonisolated public struct ActorValueHolder: Equatable, Sendable {
    public let key: ReferenceKey
    public let subject: ActorValueSubject
    public let cell: CellSceneLocation?

    public init(key: ReferenceKey, subject: ActorValueSubject, cell: CellSceneLocation? = nil) {
        self.key = key
        self.subject = subject
        self.cell = cell
    }

    /// The player, who belongs to no cell.
    public static let player = ActorValueHolder(key: .player, subject: .player, cell: nil)
}

/// One subject's maximums and regeneration rates.
nonisolated public struct ActorValueBaseline: Equatable, Sendable {
    public let maximums: ActorValues
    /// Percent of each maximum restored per second, from RACE DATA.
    public let regenPercentPerSecond: ActorValues
    /// Base values for the non-primary actor values the subject's records author,
    /// by vanilla table index. Sparse: an absent index reads
    /// `ActorValueIdentity.defaultValue(at:)`.
    public let general: [Int32: Float]
    /// The level the derivation used: the ACBS level or its `PC Level Mult` scaling
    /// for an NPC, and the character level for the player. `GetLevel` reports it.
    public let level: Int
    /// The race's `DATA` child flag, which `IsChild` reports.
    public let isChild: Bool

    public init(
        maximums: ActorValues,
        regenPercentPerSecond: ActorValues,
        general: [Int32: Float] = [:],
        level: Int = PlayerLevelSource.startingLevel,
        isChild: Bool = false
    ) {
        self.maximums = maximums
        self.regenPercentPerSecond = regenPercentPerSecond
        self.general = general
        self.level = max(PlayerLevelSource.startingLevel, level)
        self.isChild = isChild
    }

    /// The base value `index` starts from: what the records author, or the vanilla
    /// default. Nil for an index outside the table. A primary answers its re-derived
    /// maximum, which its base override is an offset from.
    public func base(at index: Int32) -> Float? {
        if let kind = ActorValueIdentity.kind(at: index) {
            return maximums[kind]
        }
        guard let fallback = ActorValueIdentity.defaultValue(at: index) else { return nil }
        return general[index] ?? fallback
    }

    /// Every actor value's derived base keyed by vanilla index, primaries
    /// included — the shape a snapshot carries so a condition and a Papyrus
    /// native can resolve an override without reaching the runtime.
    public var basesByIndex: [Int32: Float] {
        var values = general
        for kind in ActorValueKind.allCases {
            values[ActorValueIdentity.index(of: kind)] = maximums[kind]
        }
        return values
    }

    /// The same baseline reported at a different level, which is what the
    /// player's fallback needs: the numbers come from nowhere, but the level is
    /// the character's own and is known even before chargen picks a race.
    public func atLevel(_ level: Int) -> ActorValueBaseline {
        ActorValueBaseline(
            maximums: maximums,
            regenPercentPerSecond: regenPercentPerSecond,
            general: general,
            level: level
        )
    }
}

/// Re-derives actor-value baselines from plugin data.
///
/// Immutable and buildable once per load order, matching the `*Resolver`
/// convention: nothing here mutates after `init`, so it is freely readable from
/// the cell-build queue.
nonisolated public struct ActorValueBaselineResolver: Sendable {
    /// Every playable vanilla race authors the same level-1 attributes, so the
    /// player's baseline is that triple until character generation exists to
    /// pick a race. Probed rather than remembered — see
    /// docs/engine/actor-value-store.md for the records this number came from.
    public static let vanillaPlayerStartingValues = ActorValues(repeating: 100)

    /// The non-primary baselines a subject with no records behind it reads: the
    /// documented skill floor and the Creation Kit's default speed multiplier,
    /// and nothing else. A summon has no race to carry a mass or a carry
    /// weight, so both stay at the table default rather than borrowing a
    /// number from an actor it is not.
    public static let recordlessGeneralValues = ActorValueDerivation
        .generalBaseValues(inputs: ActorValueInputs())

    /// Record-side derivation. Optional so a synthetic scene, a benchmark and a
    /// unit test can drive the runtime without loading a plugin: with no
    /// resolver every actor baseline is `fallback`.
    public let resolver: ActorValueResolver?
    /// Race whose starting attributes the player uses. Nil until character
    /// generation exists, which is why `playerValues` has a fallback at all.
    public let playerRace: FormID?
    /// Baseline handed to a subject nothing can be derived for: the player
    /// before chargen, a summon, an NPC_ whose chain will not walk.
    public let fallback: ActorValueBaseline
    /// Where the player's own level is published. The same reference the resolver
    /// reads for `PC Level Mult` scaling, so the two cannot disagree.
    public let playerLevel: PlayerLevelSource

    public init(
        resolver: ActorValueResolver? = nil,
        playerRace: FormID? = nil,
        fallback: ActorValueBaseline = ActorValueBaseline(
            maximums: ActorValueBaselineResolver.vanillaPlayerStartingValues,
            regenPercentPerSecond: .zero,
            general: ActorValueBaselineResolver.recordlessGeneralValues
        ),
        playerLevel: PlayerLevelSource? = nil
    ) {
        self.resolver = resolver
        self.playerRace = playerRace
        self.fallback = fallback
        self.playerLevel = playerLevel ?? resolver?.playerLevelSource ?? PlayerLevelSource()
    }

    /// The baseline for one subject. Never throws or returns nil: a broken template
    /// chain degrades to `fallback`. `ActorValueResolver.resolve(base:)` reports the
    /// failure to a caller that wants it.
    public func baseline(for subject: ActorValueSubject) -> ActorValueBaseline {
        switch subject {
        case .player:
            playerBaseline()
        case let .actor(base):
            actorBaseline(base: base)
        case .generated:
            fallback
        }
    }

    // MARK: - Private

    private func playerBaseline() -> ActorValueBaseline {
        guard
            let resolver,
            let race = playerRace.flatMap({ resolver.races[$0.rawValue] })
        else {
            return fallback.atLevel(playerLevel.level)
        }
        return ActorValueBaseline(
            maximums: ActorValues(
                health: max(0, race.stats.startingHealth),
                magicka: max(0, race.stats.startingMagicka),
                stamina: max(0, race.stats.startingStamina)
            ),
            regenPercentPerSecond: ActorValues(
                health: race.stats.healthRegenPercent,
                magicka: race.stats.magickaRegenPercent,
                stamina: race.stats.staminaRegenPercent
            ),
            // The player has no NPC_ in this engine, so the non-primary
            // baselines come from the race alone: no ACBS speed multiplier and
            // no class spread, which is exactly the level-1 unclassed actor the
            // player is before chargen exists.
            general: ActorValueDerivation.generalBaseValues(
                inputs: ActorValueInputs(race: race.stats)
            ),
            // The player's level is the character level, not a derived one:
            // nothing in the records describes the player, and the number a
            // `PC Level Mult` actor scales against has to be the same number
            // `GetLevel` reports for them.
            level: playerLevel.level,
            isChild: race.flags.contains(.child)
        )
    }

    private func actorBaseline(base: FormID) -> ActorValueBaseline {
        guard
            let resolver,
            let resolved = try? resolver.resolve(base: base)
        else {
            return fallback
        }
        return ActorValueBaseline(
            maximums: resolved.maximums,
            regenPercentPerSecond: resolved.regenPercentPerSecond,
            general: resolved.generalBaseValues,
            level: resolved.level,
            isChild: resolved.race
                .flatMap { resolver.races[$0.rawValue]?.flags.contains(.child) } ?? false
        )
    }
}
