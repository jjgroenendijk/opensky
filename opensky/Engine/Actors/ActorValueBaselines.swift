// What an actor's values are before anything at runtime has touched them
// (issue #194, roadmap item 15.3).
//
// Baselines are never stored, exactly as inventory baselines and quest
// baselines are not: they are re-derived from plugin data on every call, so a
// reset genuinely restores whatever the records now say, and a save cannot
// carry a maximum a changed load order no longer authors.
//
// Documented in docs/engine/actor-values.md.

import Foundation

/// Which plugin record an actor's baseline comes from.
///
/// A `ReferenceKey` alone cannot answer this — the store keys state by identity
/// and knows nothing about record types — so the caller holding the placement
/// says which kind of subject it has. The shape mirrors `InventoryOwner`
/// deliberately: the two travel together at every call site that has an ACHR.
nonisolated enum ActorValueSubject: Equatable, Sendable {
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
nonisolated struct ActorValueHolder: Equatable, Sendable {
    let key: ReferenceKey
    let subject: ActorValueSubject
    let cell: CellSceneLocation?

    init(key: ReferenceKey, subject: ActorValueSubject, cell: CellSceneLocation? = nil) {
        self.key = key
        self.subject = subject
        self.cell = cell
    }

    /// The player, who belongs to no cell.
    static let player = ActorValueHolder(key: .player, subject: .player, cell: nil)
}

/// One subject's maximums and regeneration rates.
nonisolated struct ActorValueBaseline: Equatable, Sendable {
    let maximums: ActorValues
    /// Percent of each maximum restored per second, from RACE DATA.
    let regenPercentPerSecond: ActorValues
    /// Base values for the non-primary actor values the subject's records
    /// author, keyed by vanilla table index (issue #468). Sparse: an index
    /// absent here reads `ActorValueIdentity.defaultValue(at:)`.
    let general: [Int32: Float]

    init(
        maximums: ActorValues,
        regenPercentPerSecond: ActorValues,
        general: [Int32: Float] = [:]
    ) {
        self.maximums = maximums
        self.regenPercentPerSecond = regenPercentPerSecond
        self.general = general
    }

    /// The base value `index` starts from: what the records author, and the
    /// documented vanilla default otherwise. Nil for an index outside the
    /// table, which is the one answer that stays a miss.
    ///
    /// A primary answers its re-derived maximum (issue #496). That is the
    /// number a primary's base override is an offset from, and answering it
    /// here is what lets one index-keyed table cover all 164 values instead of
    /// two tables with two chances to disagree.
    func base(at index: Int32) -> Float? {
        if let kind = ActorValueIdentity.kind(at: index) {
            return maximums[kind]
        }
        guard let fallback = ActorValueIdentity.defaultValue(at: index) else { return nil }
        return general[index] ?? fallback
    }

    /// Every actor value's derived base keyed by vanilla index, primaries
    /// included — the shape a snapshot carries so a condition and a Papyrus
    /// native can resolve an override without reaching the runtime.
    var basesByIndex: [Int32: Float] {
        var values = general
        for kind in ActorValueKind.allCases {
            values[ActorValueIdentity.index(of: kind)] = maximums[kind]
        }
        return values
    }

    static let empty = ActorValueBaseline(
        maximums: .zero,
        regenPercentPerSecond: .zero
    )
}

/// Re-derives actor-value baselines from plugin data.
///
/// Immutable and buildable once per load order, matching the `*Resolver`
/// convention: nothing here mutates after `init`, so it is freely readable from
/// the cell-build queue.
nonisolated struct ActorValueBaselineResolver {
    /// Every playable vanilla race authors the same level-1 attributes, so the
    /// player's baseline is that triple until character generation exists to
    /// pick a race (M18). Probed rather than remembered — see
    /// docs/engine/actor-values.md for the `openskycli actor-values --player`
    /// output this number came from.
    static let vanillaPlayerStartingValues = ActorValues(repeating: 100)

    /// The non-primary baselines a subject with no records behind it reads: the
    /// documented skill floor and the Creation Kit's default speed multiplier,
    /// and nothing else. A summon has no race to carry a mass or a carry
    /// weight, so both stay at the table default rather than borrowing a
    /// number from an actor it is not.
    static let recordlessGeneralValues = ActorValueDerivation
        .generalBaseValues(inputs: ActorValueInputs())

    /// Record-side derivation. Optional so a synthetic scene, a benchmark and a
    /// unit test can drive the runtime without loading a plugin: with no
    /// resolver every actor baseline is `fallback`.
    let resolver: ActorValueResolver?
    /// Race whose starting attributes the player uses. Nil until character
    /// generation exists, which is why `playerValues` has a fallback at all.
    let playerRace: FormID?
    /// Baseline handed to a subject nothing can be derived for: the player
    /// before chargen, a summon, an NPC_ whose chain will not walk.
    let fallback: ActorValueBaseline

    init(
        resolver: ActorValueResolver? = nil,
        playerRace: FormID? = nil,
        fallback: ActorValueBaseline = ActorValueBaseline(
            maximums: ActorValueBaselineResolver.vanillaPlayerStartingValues,
            regenPercentPerSecond: .zero,
            general: ActorValueBaselineResolver.recordlessGeneralValues
        )
    ) {
        self.resolver = resolver
        self.playerRace = playerRace
        self.fallback = fallback
    }

    /// The baseline for one subject.
    ///
    /// Never throws and never returns nil. An NPC_ whose template chain is
    /// broken degrades to `fallback` rather than failing the mutation that
    /// asked: a cycle in someone else's plugin must not make an actor
    /// unhittable. `ActorValueResolver.resolve(base:)` is the surface that
    /// reports the failure to a caller that wants to know.
    func baseline(for subject: ActorValueSubject) -> ActorValueBaseline {
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
            return fallback
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
            // player is before chargen exists (M20).
            general: ActorValueDerivation.generalBaseValues(
                inputs: ActorValueInputs(race: race.stats)
            )
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
            general: resolved.generalBaseValues
        )
    }
}
