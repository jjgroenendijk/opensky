// The fake `CasterWorld` for the cast-loop, delivery, and readout suites.
// Answers are stored values and actions are recorded, because the suites check
// what a cast handed the world, not what the world did with it.

@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyMagic
@testable import OpenSkyMagicInterface
@testable import OpenSkyProgressionInterface
import simd

@MainActor
public final class FakeCasterWorld: CasterWorld {
    public struct Application: Equatable {
        public let entries: Int
        public let source: ActiveEffectSource
        public let caster: ReferenceKey
        public let target: ReferenceKey

        public init(
            entries: Int,
            source: ActiveEffectSource,
            caster: ReferenceKey,
            target: ReferenceKey
        ) {
            self.entries = entries
            self.source = source
            self.caster = caster
            self.target = target
        }
    }

    public var castingGameDay: Int32 = 0
    /// How many timed effects each application reports storing.
    public var storedPerApplication = 1
    /// False makes every projectile launch fail, which is what a spell whose
    /// MGEF names no resolvable PROJ does.
    public var canFireProjectile = true
    /// What the caster's aim ray finds. `.none` reaches nobody.
    public var aim = SpellAim.none
    /// How many timed effects each landed spell reports storing, per target.
    public var storedPerHitTarget = 1

    /// Skill uses the cast loop reported, recorded rather than converted.
    public private(set) var skillUses: [SkillUseEvent] = []

    @discardableResult
    public func reportSkillUse(_ use: SkillUseEvent) -> Float {
        skillUses.append(use)
        return 0
    }

    public private(set) var applications: [Application] = []
    public private(set) var firedProjectiles: [SpellPayload] = []
    public private(set) var spellHits: [SpellHit] = []
    public private(set) var aimRanges: [Float] = []
    /// Who each aim query was made for.
    public private(set) var aimCasters: [ReferenceKey] = []

    public init() {}

    public func applyCastEffects(
        _ entries: [MagicItemEffect],
        fromPlugin pluginName: String,
        source: ActiveEffectSource,
        caster: ReferenceKey,
        on target: ActorValueHolder
    ) -> Int {
        applications.append(Application(
            entries: entries.count,
            source: source,
            caster: caster,
            target: target.key
        ))
        return storedPerApplication
    }

    @discardableResult
    public func fireSpellProjectile(_ payload: SpellPayload) -> Bool {
        guard canFireProjectile else { return false }
        firedProjectiles.append(payload)
        return true
    }

    public func aimedSpellTarget(within range: Float, for caster: ReferenceKey) -> SpellAim {
        aimRanges.append(range)
        aimCasters.append(caster)
        return aim
    }

    @discardableResult
    public func applySpellHit(_ hit: SpellHit) -> SpellHitReport {
        spellHits.append(hit)
        var report = SpellHitReport()
        for _ in hit.targets {
            report.note(
                target: [],
                entries: hit.payload.entries.count,
                stored: storedPerHitTarget
            )
        }
        return report
    }
}
