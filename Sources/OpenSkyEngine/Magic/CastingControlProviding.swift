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
nonisolated public struct KnownSpellReadout: Equatable, Sendable {
    /// FULL name when the record resolves one, else its editor ID, else its
    /// key. Never empty, so a line always names something.
    public let name: String
    /// SPIT spell type, spelled for a reader: "spell", "power", "ability".
    public let typeName: String
    /// SPIT casting type, spelled for a reader.
    public let castingName: String
    /// SPIT delivery, spelled for a reader. Anything but self is the ground
    /// issue 19.8 covers, and the line says so.
    public let deliveryName: String
    /// Magicka the cast costs, which for a concentration spell is per second.
    public let cost: UInt32
    /// Seconds the cast has to be held before it can be released.
    public let chargeTime: Float
    /// Hands it is currently readied in, empty when it is not readied.
    public let readiedHands: [String]

    /// One line, the shape the readout joins with newlines.
    public var line: String {
        let readied = readiedHands.isEmpty
            ? ""
            : " — readied in \(readiedHands.joined(separator: " and "))"
        return String(
            format: "%@ (%@, %@, %@) costs %d, charge %.2fs%@",
            name, typeName, castingName, deliveryName, Int(cost), chargeTime, readied
        )
    }

    public init(
        name: String,
        typeName: String,
        castingName: String,
        deliveryName: String,
        cost: UInt32,
        chargeTime: Float,
        readiedHands: [String]
    ) {
        self.name = name
        self.typeName = typeName
        self.castingName = castingName
        self.deliveryName = deliveryName
        self.cost = cost
        self.chargeTime = chargeTime
        self.readiedHands = readiedHands
    }
}

/// One observation of the caster runtime.
nonisolated public struct CastingControlSnapshot: Equatable, Sendable {
    /// False when no caster runtime is attached — no game data, or a synthetic
    /// scene. Every other field is then empty and the panel says so rather than
    /// showing a convincing empty spellbook.
    public let isAvailable: Bool
    /// Every spell the player knows that this load order still carries, in key
    /// order.
    public let knownSpells: [KnownSpellReadout]
    /// Which known spell the panel's Ready buttons act on.
    public let selectedSpellName: String?
    /// What each hand is doing right now.
    public let leftPhase: SpellCastPhase
    public let rightPhase: SpellCastPhase
    /// Player magicka, current and maximum, so a cast's cost is legible beside
    /// what is available to pay it.
    public let magicka: Float
    public let maximumMagicka: Float
    /// Spell tomes the player carries, by display name, in inventory order.
    public let carriedTomeNames: [String]
    /// Books the player has already opened.
    public let readBookCount: Int
    /// Completed casts this session, and whole seconds of maintained casting.
    public let castCount: Int
    public let concentrationSeconds: Int
    /// Everything the runtime declined to do, for any reason.
    public let failureCount: Int
    /// The refusals seen, most frequent first, already spelled `reason x count`.
    public let failureLines: [String]
    /// Ability effect entries carrying no duration, which the active-effect
    /// runtime has no permanent mode to hold.
    public let unheldAbilityEntries: Int
    /// Spell projectiles launched this session (issue #471).
    public let projectileCount: Int
    /// Casts per delivery kind, most frequent first, already spelled
    /// `kind x count`.
    public let deliveryLines: [String]
    /// Actors the most recent landed spell reached.
    public let lastHitTargets: Int
    /// Per-entry resistance adjustments of the most recent landed spell, each
    /// already spelled `effect on target: base x multiplier = adjusted`. This
    /// is the debug-level readout the resistance rule is asserted through.
    public let lastHitAdjustments: [String]
    /// The magic condition functions evaluated against the player right now
    /// (issue #474), each already spelled `name = value` or `name: reason`.
    ///
    /// Here rather than under Runtime State because this is where the state
    /// they read is: a reader who has just readied a spell and wants to know
    /// what a condition would say about it is looking at this panel.
    public let conditionLines: [String]
    /// Human-readable result of the last panel action.
    public let lastActionText: String

    /// The reading with no runtime attached.
    public static let unavailable = CastingControlSnapshot(
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
        conditionLines: [],
        lastActionText: "Spellcasting unavailable: no game data loaded."
    )

    public init(
        isAvailable: Bool,
        knownSpells: [KnownSpellReadout],
        selectedSpellName: String?,
        leftPhase: SpellCastPhase,
        rightPhase: SpellCastPhase,
        magicka: Float,
        maximumMagicka: Float,
        carriedTomeNames: [String],
        readBookCount: Int,
        castCount: Int,
        concentrationSeconds: Int,
        failureCount: Int,
        failureLines: [String],
        unheldAbilityEntries: Int,
        projectileCount: Int,
        deliveryLines: [String],
        lastHitTargets: Int,
        lastHitAdjustments: [String],
        conditionLines: [String],
        lastActionText: String
    ) {
        self.isAvailable = isAvailable
        self.knownSpells = knownSpells
        self.selectedSpellName = selectedSpellName
        self.leftPhase = leftPhase
        self.rightPhase = rightPhase
        self.magicka = magicka
        self.maximumMagicka = maximumMagicka
        self.carriedTomeNames = carriedTomeNames
        self.readBookCount = readBookCount
        self.castCount = castCount
        self.concentrationSeconds = concentrationSeconds
        self.failureCount = failureCount
        self.failureLines = failureLines
        self.unheldAbilityEntries = unheldAbilityEntries
        self.projectileCount = projectileCount
        self.deliveryLines = deliveryLines
        self.lastHitTargets = lastHitTargets
        self.lastHitAdjustments = lastHitAdjustments
        self.conditionLines = conditionLines
        self.lastActionText = lastActionText
    }
}

@MainActor
public protocol CastingControlProviding: AnyObject {
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
