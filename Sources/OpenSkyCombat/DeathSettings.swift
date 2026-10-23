// The game settings a death reads: the push the killing hit gives the body, the chance
// the dead drop their weapon or lose their head, and when old bodies are removed. The
// wiki gives values but no rules, so each use is OpenSky's reading
// (docs/engine/ragdoll.md#death-effects).

import Foundation
import OpenSkyGameData

nonisolated public struct DeathSettings: Equatable, Sendable {
    /// One kind of attack's push: the damage range, and the force it maps to.
    nonisolated public struct ForceRange: Equatable, Sendable {
        public var damageMin: Float
        public var damageMax: Float
        public var forceMin: Float
        public var forceMax: Float

        public init(damageMin: Float, damageMax: Float, forceMin: Float, forceMax: Float) {
            self.damageMin = damageMin
            self.damageMax = damageMax
            self.forceMin = forceMin
            self.forceMax = forceMax
        }

        /// The force for `damage`, blended between the two ends and held at them.
        public func force(for damage: Float) -> Float {
            let span = damageMax - damageMin
            let unit = span > 0 && damage.isFinite
                ? min(max((damage - damageMin) / span, 0), 1)
                : damage >= damageMax ? 1 : 0
            let force = forceMin + (forceMax - forceMin) * unit
            return force.isFinite ? max(force, 0) : 0
        }
    }

    /// `fDeathForceDamageMin`, `...Max`, `fDeathForceForceMin`, `...Max`.
    public var melee = ForceRange(damageMin: 1, damageMax: 40, forceMin: 4, forceMax: 12)
    /// `fDeathForceRangedDamageMin`, `...Max`, `fDeathForceRangedForceMin`, `...Max`.
    public var ranged = ForceRange(damageMin: 1, damageMax: 50, forceMin: 10, forceMax: 30)
    /// `fDeathForceSpellImpactMult`: a spell pushes as a ranged hit times this.
    public var spellImpactMult: Float = 2
    /// `iDeathDropWeaponChance`, in percent.
    public var dropWeaponChance = 100
    /// `iCombatDismemberPartChance`, in percent.
    public var dismemberChance = 50
    /// `iRemoveExcessDeadCount`: more dead than this, and the oldest go.
    public var excessDeadCount = 15
    /// `fRemoveExcessDeadTime`: seconds a body must be dead before it can go.
    public var excessDeadSeconds: Float = 10
    /// `fEssentialDeathTime`: seconds an essential actor stays in bleedout.
    public var bleedoutSeconds: Float = 20
    /// `fBleedoutDefault`: the health share at which an actor kneels when its class
    /// gives no ratio. Read from the name; no open source defines it.
    public var bleedoutThreshold: Float = 0.15

    public static let vanilla = Self()

    public init() {}

    public static func resolve(store: GameSettingStore) -> Self {
        var settings = vanilla
        let fields: [(String, WritableKeyPath<Self, Float>)] = [
            ("fDeathForceDamageMin", \.melee.damageMin),
            ("fDeathForceDamageMax", \.melee.damageMax),
            ("fDeathForceForceMin", \.melee.forceMin),
            ("fDeathForceForceMax", \.melee.forceMax),
            ("fDeathForceRangedDamageMin", \.ranged.damageMin),
            ("fDeathForceRangedDamageMax", \.ranged.damageMax),
            ("fDeathForceRangedForceMin", \.ranged.forceMin),
            ("fDeathForceRangedForceMax", \.ranged.forceMax),
            ("fDeathForceSpellImpactMult", \.spellImpactMult),
            ("fRemoveExcessDeadTime", \.excessDeadSeconds),
            ("fEssentialDeathTime", \.bleedoutSeconds),
            ("fBleedoutDefault", \.bleedoutThreshold)
        ]
        for (editorID, keyPath) in fields {
            store.read(editorID, into: &settings, keyPath)
        }
        store.read("iDeathDropWeaponChance", into: &settings, \.dropWeaponChance)
        store.read("iCombatDismemberPartChance", into: &settings, \.dismemberChance)
        store.read("iRemoveExcessDeadCount", into: &settings, \.excessDeadCount)
        return settings
    }

    /// The push of a killing hit, in Havok force units. A hit with no attack behind it
    /// gives none; the body only falls.
    public func force(of hit: CombatHitRecord) -> Float {
        switch hit.kind {
        case .melee: melee.force(for: hit.damage)
        case .ranged: ranged.force(for: hit.damage)
        case .spell: ranged.force(for: hit.damage) * spellMult
        case .other: 0
        }
    }

    private var spellMult: Float {
        spellImpactMult.isFinite ? max(spellImpactMult, 0) : 0
    }

    /// The Death & Ragdoll readout's settings line.
    public var readout: String {
        String(
            format: "Death settings: melee push %.0f-%.0f for %.0f-%.0f damage · ranged %.0f-%.0f "
                + "for %.0f-%.0f · spell x%.1f · drop weapon %d%% · dismember %d%% · "
                + "bodies over %d go after %.0f s",
            melee.forceMin, melee.forceMax, melee.damageMin, melee.damageMax,
            ranged.forceMin, ranged.forceMax, ranged.damageMin, ranged.damageMax,
            spellImpactMult, dropWeaponChance, dismemberChance, excessDeadCount, excessDeadSeconds
        )
    }
}
