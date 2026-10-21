// The spellcasting panel's seam: learn, read, ready and cast, without
// `GameViewController`. One snapshot value, so the readout comes from a single
// observation.

import Foundation
import OpenSkyMagicInterface

/// One known spell as a panel spells it.
nonisolated public struct KnownSpellReadout: Equatable, Sendable {
    /// FULL name when the record resolves one, else its editor ID, else its
    /// key. Never empty, so a line always names something.
    public let name: String
    /// SPIT spell type, spelled for a reader: "spell", "power", "ability".
    public let typeName: String
    /// SPIT casting type, spelled for a reader.
    public let castingName: String
    /// SPIT delivery, spelled for a reader.
    public let deliveryName: String
    /// Magicka the cast costs, which for a concentration spell is per second.
    public let cost: UInt32
    /// Seconds the cast has to be held before it can be released.
    public let chargeTime: Float
    /// Hands it is currently readied in, empty when it is not readied.
    public let readiedHands: [String]
    /// The school of its costliest effect, nil when that is not a magic school.
    public let schoolName: String?

    /// One line, the shape the readout joins with newlines.
    public var line: String {
        let readied = readiedHands.isEmpty
            ? ""
            : " — readied in \(readiedHands.joined(separator: " and "))"
        let kinds = ([schoolName].compactMap(\.self) + [typeName, castingName, deliveryName])
            .joined(separator: ", ")
        return String(
            format: "%@ (%@) costs %d, charge %.2fs%@",
            name, kinds, Int(cost), chargeTime, readied
        )
    }

    public init(
        name: String,
        typeName: String,
        castingName: String,
        deliveryName: String,
        cost: UInt32,
        chargeTime: Float,
        readiedHands: [String],
        schoolName: String? = nil
    ) {
        self.name = name
        self.typeName = typeName
        self.castingName = castingName
        self.deliveryName = deliveryName
        self.cost = cost
        self.chargeTime = chargeTime
        self.readiedHands = readiedHands
        self.schoolName = schoolName
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
    /// Effects the player's known abilities hold right now.
    public let abilityEffectCount: Int
    /// Spell projectiles launched this session.
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
    /// The magic condition functions for the player now, each as `name = value` or
    /// `name: reason`. Here, beside the readied spells they read.
    public let conditionLines: [String]
    /// Human-readable result of the last panel action.
    public let lastActionText: String
    /// One line per carried soul gem copy, then the last soul trap.
    public var soulLines: [String] = []
    /// The runes waiting on the ground, then how many went off.
    public var runeText = "Runes: none"
    /// The actors the player's summons and reanimations command.
    public var commandedText = "Commanded: none"

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
        abilityEffectCount: 0,
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
        abilityEffectCount: Int,
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
        self.abilityEffectCount = abilityEffectCount
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
    @discardableResult
    func grantPlayerStartSpells() -> CastingActionOutcome

    /// Opens the first spell tome the player carries.
    @discardableResult
    func readFirstCarriedSpellTome() -> CastingActionOutcome

    /// Reads the first skill book the player carries and has not read.
    @discardableResult
    func readFirstUnreadSkillBook() -> CastingActionOutcome

    /// Moves the panel's selection to the next known spell, wrapping.
    @discardableResult
    func selectNextKnownSpell() -> CastingActionOutcome

    /// Readies the selected spell in one hand.
    @discardableResult
    func readySelectedSpell(in hand: SpellHand) -> CastingActionOutcome

    /// Runs one whole cast in `hand` with no button: charge, then release, so the panel
    /// alone can verify it. Returns a readable outcome the panel shows verbatim.
    @discardableResult
    func castReadiedSpell(in hand: SpellHand) -> CastingActionOutcome

    /// Begins both hands together and runs the whole cast, so a dual cast can be
    /// checked without two buttons.
    @discardableResult
    func castReadiedSpellWithBothHands() -> CastingActionOutcome

    /// Recharges the equipped enchanted weapon from a carried filled soul gem.
    @discardableResult
    func rechargeEquippedWeapon() -> RechargeOutcome
}
