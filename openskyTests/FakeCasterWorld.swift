// The fake `CasterWorld` the cast-loop suites drive (issue #470, roadmap item
// 19.7; extended for aimed delivery in issue #471, item 19.8).
//
// Its own file rather than a member of one suite, because three now use it —
// the cast loop, the delivery half, and the panel readout — and the seam it
// stands in for is what makes all three testable with no renderer, no window
// and no game data.
//
// Every answer is a plain stored value and every action is recorded rather than
// performed: what these suites need to know is what a cast *handed* the world,
// entry by entry, not what the world then did with it.

@testable import opensky
import simd

@MainActor
final class FakeCasterWorld: CasterWorld {
    struct Application: Equatable {
        let entries: Int
        let source: ActiveEffectSource
        let caster: ReferenceKey
        let target: ReferenceKey
    }

    var castingGameDay: Int32 = 0
    /// How many timed effects each application reports storing.
    var storedPerApplication = 1
    /// False makes every projectile launch fail, which is what a spell whose
    /// MGEF names no resolvable PROJ does.
    var canFireProjectile = true
    /// What the caster's aim ray finds. `.none` reaches nobody.
    var aim = SpellAim.none
    /// How many timed effects each landed spell reports storing, per target.
    var storedPerHitTarget = 1

    private(set) var applications: [Application] = []
    private(set) var firedProjectiles: [SpellPayload] = []
    private(set) var spellHits: [SpellHit] = []
    private(set) var aimRanges: [Float] = []
    /// Who each aim query was made for (issue #473).
    private(set) var aimCasters: [ReferenceKey] = []

    func applyCastEffects(
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
    func fireSpellProjectile(_ payload: SpellPayload) -> Bool {
        guard canFireProjectile else { return false }
        firedProjectiles.append(payload)
        return true
    }

    func aimedSpellTarget(within range: Float, for caster: ReferenceKey) -> SpellAim {
        aimRanges.append(range)
        aimCasters.append(caster)
        return aim
    }

    @discardableResult
    func applySpellHit(_ hit: SpellHit) -> SpellHitReport {
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
