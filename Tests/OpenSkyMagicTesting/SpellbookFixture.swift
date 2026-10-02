// Synthetic SPEL, EQUP, MGEF and BOOK records for the caster suites. The
// spell shapes match vanilla records read with `openskycli record`.
// Layouts: UESP "Skyrim Mod:Mod File Format" /SPEL, /EQUP, /MGEF, /BOOK.

import FormatsESMTesting
import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData

@MainActor
public enum SpellbookFixture {
    public static let pluginName = "Base.esm"

    public enum Slot {
        public static let rightHand: UInt32 = 0x0100
        public static let leftHand: UInt32 = 0x0110
        public static let eitherHand: UInt32 = 0x0120
        public static let bothHands: UInt32 = 0x0130
        public static let voice: UInt32 = 0x0150
    }

    public enum Spell {
        /// Fire and forget, self, 0.5 s charge, one instant restore-health
        /// entry. The acceptance picture's spell.
        public static let fastHealing: UInt32 = 0x0200
        /// Concentration, self, no charge, one one-second restore entry.
        public static let healing: UInt32 = 0x0210
        /// Fire and forget, self, two-handed slot.
        public static let masterHeal: UInt32 = 0x0220
        /// Fire and forget, aimed — the delivery 19.8 owns.
        public static let firebolt: UInt32 = 0x0230
        /// A greater power, self, once per day.
        public static let dragonskin: UInt32 = 0x0240
        /// An ability with one timed entry and one zero-duration entry.
        public static let resistFire: UInt32 = 0x0250
        /// Fire and forget, self, named `Flames` so the load-order lookup
        /// `SpellStore.vanillaStartSpellEditorIDs` performs finds it.
        public static let flames: UInt32 = 0x0260
        /// Fire and forget, aimed, one hostile fire entry with an area, plus a
        /// point entry: the shape of vanilla `Fireball`.
        public static let fireball: UInt32 = 0x0270
        /// Fire and forget, aimed, hostile, with the SPEL "Ignore Resistance"
        /// flag set.
        public static let unresistedBolt: UInt32 = 0x0280
        /// Concentration, aimed — the flamethrower shape.
        public static let flamestream: UInt32 = 0x0290
        /// Fire and forget, target actor.
        public static let sparkAtTarget: UInt32 = 0x02A0
        /// Fire and forget, touch — a delivery 19.8 counts rather than carries
        /// out.
        public static let touchOfDeath: UInt32 = 0x02B0
    }

    public enum Book {
        /// Teaches `Spell.healing`.
        public static let healingTome: UInt32 = 0x0300
        /// Teaches nothing, so reading it marks the book and grants no spell.
        public static let novel: UInt32 = 0x0310
    }

    public static func key(_ objectID: UInt32) -> ReferenceKey {
        .plugin(name: pluginName.lowercased(), objectID: objectID)
    }

    // MARK: - Stores

    public static func plugin(extraRecords: [Data] = []) throws -> ESMFile {
        try ESMFixture.plugin(
            records: equipSlots + magicEffects + projectiles + spells + books + extraRecords
        )
    }

    /// Every fixture record in one index, which is what each store below is
    /// built over. Built once per call rather than cached, so a suite that
    /// mutates nothing shares nothing.
    public static func index() throws -> RecordIndex {
        try RecordIndex(
            plugins: [(pluginName, plugin())],
            recordTypes: ["MGEF", "SPEL", "SCRL", "EQUP", "PROJ"]
        )
    }

    /// The MGEF lookup behind every EFID, for a suite that needs a real effect
    /// runtime.
    public static func effectStore(index: RecordIndex) -> MagicEffectStore {
        MagicEffectStore(index: index)
    }

    /// The PROJ lookup an aimed cast resolves its projectile through — the
    /// same index the arrow path reads, over the fixture's own records.
    public static func projectileStore() throws -> ItemDefinitionStore {
        try ItemDefinitionStore(file: plugin())
    }
}
