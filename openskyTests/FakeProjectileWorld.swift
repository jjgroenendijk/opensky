// The fake `ProjectileWorld` the archery runtime tests drive (issue #196,
// roadmap item 15.5).
//
// Its own file rather than a member of one test suite, because three suites
// use it — the projectile runtime, the archery runtime, and the panel readout —
// and the seam it stands in for is what makes all three testable with no
// renderer, no window and no game data.
//
// Every answer is a plain stored value, and every action is recorded rather
// than performed. Static collision is a list of half-space planes instead of a
// real broadphase: what the runtime needs from a sweep is a distance and a
// point, and standing up a `StaticCollisionSet` here would test
// `ShapeSweeper` a second time rather than testing the runtime.

@testable import opensky
import simd

@MainActor
final class FakeProjectileWorld: ProjectileWorld {
    /// One flat wall perpendicular to +X, which is all a trajectory test needs
    /// to hit.
    struct Wall {
        let x: Float
        let reference: FormID
    }

    var shooter = ProjectileShooter(
        key: .player,
        origin: SIMD3<Float>(),
        aim: SIMD3<Float>(1, 0, 0),
        isFirstPerson: true,
        location: .exterior(CellCoordinate(x: 0, y: 0))
    )
    var targets: [MeleeTarget] = []
    var wall: Wall?
    var material: FormID?
    /// How many arrows the fake quiver holds. Zero makes `consumeArrow` fail,
    /// which is what an empty quiver does.
    var arrowCount = 10
    /// False makes every spawn fail, which is what a session with no cell does.
    var canSpawn = true
    var residentCells: Set<CellSceneLocation> = [.exterior(CellCoordinate(x: 0, y: 0))]

    /// Skill uses the runtime reported (issue #498), recorded rather than
    /// converted.
    private(set) var skillUses: [SkillUseEvent] = []

    @discardableResult
    func reportSkillUse(_ use: SkillUseEvent) -> Float {
        skillUses.append(use)
        return 0
    }

    private(set) var damage: [ReferenceKey: Float] = [:]
    private(set) var consumed: [FormID] = []
    private(set) var spawned: [StuckProjectile] = []
    private(set) var removed: [ReferenceKey] = []
    private(set) var impacts: [ResolvedMeleeImpact] = []
    private(set) var raised: [String] = []
    private(set) var spellHits: [SpellHit] = []
    /// Enchanted hits the runtime handed out (issue #472).
    private(set) var enchantedHits: [WeaponEnchantmentHit] = []
    private(set) var variables: [String: BehaviorVariableValue] = [:]
    private var nextSpawnID: UInt64 = 1

    /// Stuck arrows still in the world, which is what the cap and the eviction
    /// rule are asserted against.
    var liveStuckKeys: [ReferenceKey] {
        spawnedKeys.filter { !removed.contains($0) }
    }

    private var spawnedKeys: [ReferenceKey] = []

    var projectileShooter: ProjectileShooter {
        shooter
    }

    func projectileTargets() -> [MeleeTarget] {
        targets
    }

    func sweepProjectile(_ query: ShapeSweepQuery) -> ShapeSweepHit? {
        guard let wall else { return nil }
        let direction = query.normalizedDirection
        guard direction.x > 0 else { return nil }
        let distance = (wall.x - query.first.x) / direction.x
        guard distance >= 0, distance <= query.maximumDistance else { return nil }
        return ShapeSweepHit(
            reference: wall.reference,
            distance: distance,
            position: query.first + direction * distance,
            normal: SIMD3(-1, 0, 0),
            startsOverlapping: false
        )
    }

    func projectileMaterial(at position: SIMD3<Float>) -> FormID? {
        material
    }

    @discardableResult
    func applyProjectileDamage(_ amount: Float, to target: ReferenceKey) -> Bool {
        damage[target, default: 0] += amount
        return true
    }

    func playProjectileImpact(_ impact: ResolvedMeleeImpact, at position: SIMD3<Float>) {
        impacts.append(impact)
    }

    @discardableResult
    func consumeArrow(_ ammunition: FormID) -> Bool {
        guard arrowCount > 0 else { return false }
        arrowCount -= 1
        consumed.append(ammunition)
        return true
    }

    @discardableResult
    func spawnStuckProjectile(_ arrow: StuckProjectile) -> ReferenceKey? {
        guard canSpawn else { return nil }
        spawned.append(arrow)
        let key = ReferenceKey.generated(nextSpawnID)
        nextSpawnID += 1
        spawnedKeys.append(key)
        return key
    }

    func removeStuckProjectile(_ key: ReferenceKey) {
        removed.append(key)
    }

    func residentProjectileCells() -> Set<CellSceneLocation> {
        residentCells
    }

    @discardableResult
    func raiseArcheryEvent(_ name: String) -> Bool {
        raised.append(name)
        return true
    }

    func writeArcheryVariable(_ value: BehaviorVariableValue, named name: String) {
        variables[name] = value
    }

    /// Records the landed spell instead of applying it (issue #471). What the
    /// projectile suites need to know is which actors the runtime *reached* and
    /// at what distance; whether the effect runtime then stored anything is
    /// `SpellHitTests`' question, asked against a real one.
    @discardableResult
    func applySpellHit(_ hit: SpellHit) -> SpellHitReport {
        spellHits.append(hit)
        var report = SpellHitReport()
        for _ in hit.targets {
            report.note(target: [], entries: hit.payload.entries.count, stored: 0)
        }
        return report
    }

    /// Records the enchanted hit instead of applying it, for the reason a landed
    /// spell is recorded (issue #472): what the projectile suites need to know is
    /// that the bow's enchantment reached the seam with the right target and
    /// position, and `EnchantmentRuntimeTests` asks what applying it does against a
    /// real effect runtime. The charge is reported unspent, because nothing here
    /// owns a world-state store to spend it in.
    @discardableResult
    func applyWeaponEnchantment(_ hit: WeaponEnchantmentHit) -> WeaponEnchantmentReport? {
        enchantedHits.append(hit)
        return WeaponEnchantmentReport(
            item: hit.profile.item,
            name: hit.profile.name,
            charge: hit.profile.fullCharge,
            didFire: true,
            entryCount: hit.profile.entries.count,
            storedCount: 0,
            adjustments: []
        )
    }
}
