// The crime numbers that come from game settings, not from a faction's `CRVA`: the
// default prices a "Use Defaults" faction charges, the jail sentence, how far an
// alarm reaches a guard, and the trespass grace period. Defaults are the CK wiki's
// Category:Settings values. See docs/engine/crime.md and docs/engine/jail.md.

import OpenSkyFormatsESM
import OpenSkyGameData

/// The prices a crime faction with the `crimeGoldUseDefaults` flag charges.
nonisolated public struct CrimePrices: Equatable, Sendable {
    public var murder: Int32
    public var assault: Int32
    public var trespass: Int32
    public var pickpocket: Int32
    /// Nil on a 12-byte `CRVA`, which `CrimeGoldTable` reads as a multiplier of 1.
    public var stealMultiplier: Float?
    public var escape: Int32
    public var werewolf: Int32

    public init(
        murder: Int32, assault: Int32, trespass: Int32, pickpocket: Int32,
        stealMultiplier: Float?, escape: Int32, werewolf: Int32
    ) {
        self.murder = murder
        self.assault = assault
        self.trespass = trespass
        self.pickpocket = pickpocket
        self.stealMultiplier = stealMultiplier
        self.escape = escape
        self.werewolf = werewolf
    }

    private static func price(_ value: (some BinaryInteger)?, or fallback: Int32) -> Int32 {
        value.map { Int32(clamping: $0) } ?? fallback
    }

    /// The prices a faction's own `CRVA` sets. A short record has no escape or
    /// werewolf price, so those fall back to the defaults.
    public init(values: Faction.CrimeValues, defaults: CrimePrices) {
        self.init(
            murder: Int32(values.murder), assault: Int32(values.assault),
            trespass: Int32(values.trespass), pickpocket: Int32(values.pickpocket),
            stealMultiplier: values.stealMultiplier,
            escape: Self.price(values.escape, or: defaults.escape),
            werewolf: Self.price(values.werewolf, or: defaults.werewolf)
        )
    }
}

nonisolated public struct CrimeSettings: Equatable, Sendable {
    /// `iCrimeGoldMurder`, `iCrimeGoldAttack`, `iCrimeGoldTrespass`,
    /// `iCrimeGoldPickpocket`, `fCrimeGoldSteal`, `iCrimeGoldEscape`, and
    /// `iCrimeGoldWerewolf`.
    public var defaultPrices = CrimePrices(
        murder: 1000, assault: 40, trespass: 5, pickpocket: 25,
        stealMultiplier: 0.5, escape: 100, werewolf: 1000
    )
    /// `iCrimeDaysInPrisonMod`: gold of bounty per day of sentence.
    public var goldPerJailDay = 100
    /// `iCrimeMaxNumberofDaysinJail`: the longest sentence.
    public var maximumJailDays = 7
    /// `iCrimeAlarmRecDistance`: how far, in world units, a witness's alarm reaches
    /// a guard. That this is the setting's meaning is OpenSky's reading of its name.
    public var alarmDistance: Float = 4000
    /// UESP "Skyrim:Crime": "you will receive a bounty after 30 seconds". No setting
    /// holds it.
    public var trespassGraceSeconds: Double = 30
    /// `iTrespassWarnings`: how many times an owner warns before the grace period.
    public var trespassWarnings = 2
    /// `iAttackOnSightViolent`: violent gold above this makes an attack-on-sight
    /// faction's guards fight instead of talking.
    public var attackOnSightViolent: Int32 = 2999
    /// `iAttackOnSightNonViolent`, the same for non-violent gold. Its default 0 is
    /// read as "off", because guards arrest a thief with any bounty.
    public var attackOnSightNonViolent: Int32 = 0

    public static let vanilla = Self()

    public init() {}

    /// The prices one faction charges: the defaults when it sets "Use Defaults",
    /// its own `CRVA` otherwise, and nil when it has neither.
    public func prices(for faction: Faction) -> CrimePrices? {
        if faction.flags.contains(.crimeGoldUseDefaults) {
            return defaultPrices
        }
        return faction.crimeValues.map { CrimePrices(values: $0, defaults: defaultPrices) }
    }

    /// Whether an attack-on-sight faction's guards fight over this gold.
    public func attacksOnSight(nonViolent: Int32, violent: Int32) -> Bool {
        violent > attackOnSightViolent
            || (attackOnSightNonViolent > 0 && nonViolent > attackOnSightNonViolent)
    }

    /// Days served for `bounty`: one per `goldPerJailDay`, at least one, at most
    /// `maximumJailDays`.
    public func sentenceDays(bounty: Int32) -> Int {
        guard bounty > 0 else { return 0 }
        let perDay = max(1, goldPerJailDay)
        return min(max(1, maximumJailDays), max(1, Int(bounty) / perDay))
    }

    public static func resolve(store: GameSettingStore) -> Self {
        func gold(_ editorID: String, _ fallback: Int32) -> Int32 {
            store.integer(editorID).map { Int32(clamping: max(0, $0)) } ?? fallback
        }
        var settings = vanilla
        let defaults = settings.defaultPrices
        settings.defaultPrices = CrimePrices(
            murder: gold("iCrimeGoldMurder", defaults.murder),
            assault: gold("iCrimeGoldAttack", defaults.assault),
            trespass: gold("iCrimeGoldTrespass", defaults.trespass),
            pickpocket: gold("iCrimeGoldPickpocket", defaults.pickpocket),
            stealMultiplier: store.number("fCrimeGoldSteal") ?? defaults.stealMultiplier,
            escape: gold("iCrimeGoldEscape", defaults.escape),
            werewolf: gold("iCrimeGoldWerewolf", defaults.werewolf)
        )
        settings.attackOnSightViolent = gold("iAttackOnSightViolent", settings.attackOnSightViolent)
        settings.attackOnSightNonViolent = gold(
            "iAttackOnSightNonViolent", settings.attackOnSightNonViolent
        )
        store.read("iCrimeDaysInPrisonMod", into: &settings, \.goldPerJailDay)
        store.read("iCrimeMaxNumberofDaysinJail", into: &settings, \.maximumJailDays)
        store.read("iTrespassWarnings", into: &settings, \.trespassWarnings)
        store.read("iCrimeAlarmRecDistance", into: &settings, \.alarmDistance)
        return settings
    }
}
