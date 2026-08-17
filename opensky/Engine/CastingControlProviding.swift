// Main-app spellcasting seam (issue #470, roadmap item 19.7). The provider keeps
// the panel independent of `GameViewController` while exposing the engine-owned
// learn, read, ready and cast operations.
//
// One snapshot value rather than a bag of protocol properties, for the same
// reason `MagicEffectControlSnapshot` is one: the readout has to be a pure
// function of a single engine observation, not of several taken microseconds
// apart while the simulation is mutating between them.
//
// AppKit-free, so it compiles into `openskycli` alongside the app.

import Foundation

/// One known spell as a panel spells it.
nonisolated struct KnownSpellReadout: Equatable, Sendable {
    /// FULL name when the record resolves one, else its editor ID, else its
    /// key. Never empty, so a line always names something.
    let name: String
    /// SPIT spell type, spelled for a reader: "spell", "power", "ability".
    let typeName: String
    /// SPIT casting type, spelled for a reader.
    let castingName: String
    /// SPIT delivery, spelled for a reader. Anything but self is the ground
    /// issue 19.8 covers, and the line says so.
    let deliveryName: String
    /// Magicka the cast costs, which for a concentration spell is per second.
    let cost: UInt32
    /// Seconds the cast has to be held before it can be released.
    let chargeTime: Float
    /// Hands it is currently readied in, empty when it is not readied.
    let readiedHands: [String]

    /// One line, the shape the readout joins with newlines.
    var line: String {
        let readied = readiedHands.isEmpty
            ? ""
            : " — readied in \(readiedHands.joined(separator: " and "))"
        return String(
            format: "%@ (%@, %@, %@) costs %d, charge %.2fs%@",
            name, typeName, castingName, deliveryName, Int(cost), chargeTime, readied
        )
    }
}

/// One observation of the caster runtime.
nonisolated struct CastingControlSnapshot: Equatable, Sendable {
    /// False when no caster runtime is attached — no game data, or a synthetic
    /// scene. Every other field is then empty and the panel says so rather than
    /// showing a convincing empty spellbook.
    let isAvailable: Bool
    /// Every spell the player knows that this load order still carries, in key
    /// order.
    let knownSpells: [KnownSpellReadout]
    /// Which known spell the panel's Ready buttons act on.
    let selectedSpellName: String?
    /// What each hand is doing right now.
    let leftPhase: SpellCastPhase
    let rightPhase: SpellCastPhase
    /// Player magicka, current and maximum, so a cast's cost is legible beside
    /// what is available to pay it.
    let magicka: Float
    let maximumMagicka: Float
    /// Spell tomes the player carries, by display name, in inventory order.
    let carriedTomeNames: [String]
    /// Books the player has already opened.
    let readBookCount: Int
    /// Completed casts this session, and whole seconds of maintained casting.
    let castCount: Int
    let concentrationSeconds: Int
    /// Everything the runtime declined to do, for any reason.
    let failureCount: Int
    /// The refusals seen, most frequent first, already spelled `reason x count`.
    let failureLines: [String]
    /// Ability effect entries carrying no duration, which the active-effect
    /// runtime has no permanent mode to hold.
    let unheldAbilityEntries: Int
    /// Spell projectiles launched this session (issue #471).
    let projectileCount: Int
    /// Casts per delivery kind, most frequent first, already spelled
    /// `kind x count`.
    let deliveryLines: [String]
    /// Actors the most recent landed spell reached.
    let lastHitTargets: Int
    /// Per-entry resistance adjustments of the most recent landed spell, each
    /// already spelled `effect on target: base x multiplier = adjusted`. This
    /// is the debug-level readout the resistance rule is asserted through.
    let lastHitAdjustments: [String]
    /// Human-readable result of the last panel action.
    let lastActionText: String

    /// The reading with no runtime attached.
    static let unavailable = CastingControlSnapshot(
        isAvailable: false,
        knownSpells: [],
        selectedSpellName: nil,
        leftPhase: .idle,
        rightPhase: .idle,
        magicka: 0,
        maximumMagicka: 0,
        carriedTomeNames: [],
        readBookCount: 0,
        castCount: 0,
        concentrationSeconds: 0,
        failureCount: 0,
        failureLines: [],
        unheldAbilityEntries: 0,
        projectileCount: 0,
        deliveryLines: [],
        lastHitTargets: 0,
        lastHitAdjustments: [],
        lastActionText: "Spellcasting unavailable: no game data loaded."
    )
}

@MainActor
protocol CastingControlProviding: AnyObject {
    var castingControlSnapshot: CastingControlSnapshot { get }

    /// Grants every spell the load order flags as a player start spell.
    ///
    /// - Returns: a human-readable outcome, which the panel shows verbatim.
    @discardableResult
    func grantPlayerStartSpells() -> String

    /// Opens the first spell tome the player carries.
    ///
    /// - Returns: a human-readable outcome, which the panel shows verbatim.
    @discardableResult
    func readFirstCarriedSpellTome() -> String

    /// Moves the panel's selection to the next known spell, wrapping.
    ///
    /// - Returns: a human-readable outcome, which the panel shows verbatim.
    @discardableResult
    func selectNextKnownSpell() -> String

    /// Readies the selected spell in one hand.
    ///
    /// - Returns: a human-readable outcome, which the panel shows verbatim.
    @discardableResult
    func readySelectedSpell(in hand: SpellHand) -> String

    /// Runs one whole cast in `hand` without the player holding a button: the
    /// charge is fast-forwarded, then the cast is released.
    ///
    /// Exists beside the held-button path so the behaviour is verifiable from
    /// the panel alone, which is what makes it the milestone's evidence.
    ///
    /// - Returns: a human-readable outcome, which the panel shows verbatim.
    @discardableResult
    func castReadiedSpell(in hand: SpellHand) -> String
}
