// The 19.8 acceptance chain against the user's own install (issue #471),
// headless: a vanilla destruction spell is readied and cast at an actor, its
// projectile flies on the record's own numbers, and the health it takes off is
// the resistance-adjusted amount rather than the authored one.
//
// Read-only throughout, and no game bytes leave the machine: what is asserted
// is arithmetic over actor values this session set, and the summary written to
// gitignored `logs/` names editor IDs and numbers only.
//
// This is the deterministic half of the acceptance. It drives the real
// `CasterRuntime`, the real `ProjectileRuntime` and the real
// `ActiveEffectRuntime` over records read from the install; what it stands in
// for is the renderer and the streamer, because a spell projectile is invisible
// until M26 and there would be nothing in a frame to look at.

import Foundation
@testable import opensky
import simd
import Testing

struct SpellDeliveryAcceptanceRealDataTests {
    private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    /// The spell the picture uses: vanilla `Firebolt`, aimed, fire and forget,
    /// one hostile Fire Damage entry resisted through `Resist Fire`.
    private static let pinnedSpell = "Firebolt"
    /// The actor it is cast at. A synthetic reference rather than a streamed
    /// ACHR: what the chain needs from a target is an actor-value holder, and
    /// standing up the streamer would test cell loading a second time.
    private static let victim = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x00F0_0001)
    /// Percentage points of `Resist Fire` the victim carries, so the landed
    /// damage is visibly not the authored magnitude.
    private static let resistFirePoints: Float = 40

    /// The one world both runtimes resolve against: it answers where the caster
    /// aims, who is standing there, and routes a landed spell into the real
    /// effect runtime exactly as `GameViewController` does.
    @MainActor
    private final class AcceptanceWorld: CasterWorld, ProjectileWorld {
        var effects: ActiveEffectRuntime
        let items: ItemDefinitionStore
        let projectiles: ProjectileRuntime
        let holder: ActorValueHolder
        var castingGameDay: Int32 = 0
        private(set) var reports: [SpellHitReport] = []

        init(
            effects: ActiveEffectRuntime,
            items: ItemDefinitionStore,
            projectiles: ProjectileRuntime,
            holder: ActorValueHolder
        ) {
            self.effects = effects
            self.items = items
            self.projectiles = projectiles
            self.holder = holder
        }

        // MARK: Casting

        func applyCastEffects(
            _ entries: [MagicItemEffect],
            fromPlugin pluginName: String,
            source: ActiveEffectSource,
            caster: ReferenceKey,
            on target: ActorValueHolder
        ) -> Int {
            effects.apply(
                entries, fromPlugin: pluginName, source: source, caster: caster, on: target
            ).count
        }

        @discardableResult
        func fireSpellProjectile(_ payload: SpellPayload) -> Bool {
            guard
                let link = payload.projectile,
                let profile = items.projectileProfile(link)
            else { return false }
            return projectiles.fire(
                ProjectileShot.spell(profile: profile, payload: payload)
            ) != nil
        }

        func aimedSpellTarget(within range: Float, for caster: ReferenceKey) -> SpellAim {
            SpellAim(target: holder.key, position: SIMD3(), candidates: projectileTargets())
        }

        @discardableResult
        func applySpellHit(_ hit: SpellHit) -> SpellHitReport {
            let report = SpellHitApplication.apply(
                hit, holders: [holder.key: holder], using: &effects
            )
            reports.append(report)
            return report
        }

        /// This chain casts spells, not swings: the weapons it carries are
        /// unenchanted, so an enchanted hit is the documented "not here" nil
        /// (issue #472). `EnchantmentRuntimeRealDataTests` covers the enchantment
        /// side against the same install.
        @discardableResult
        func applyWeaponEnchantment(_ hit: WeaponEnchantmentHit) -> WeaponEnchantmentReport? {
            nil
        }

        // MARK: Projectiles

        /// The caster stands at the origin looking down +X; the target is 600
        /// units away, which is inside every vanilla bolt's range.
        var projectileShooter: ProjectileShooter {
            ProjectileShooter(
                key: .player,
                origin: SIMD3(0, 0, 100),
                aim: SIMD3(1, 0, 0),
                isFirstPerson: true,
                location: nil
            )
        }

        func projectileTargets() -> [MeleeTarget] {
            [MeleeTarget(key: holder.key, feet: SIMD3(600, 0, 0))]
        }

        func sweepProjectile(_ query: ShapeSweepQuery) -> ShapeSweepHit? {
            nil
        }

        func projectileMaterial(at position: SIMD3<Float>) -> FormID? {
            nil
        }

        @discardableResult
        func applyProjectileDamage(_ amount: Float, to target: ReferenceKey) -> Bool {
            false
        }

        func playProjectileImpact(_ impact: ResolvedMeleeImpact, at position: SIMD3<Float>) {}
        @discardableResult
        func consumeArrow(_ ammunition: FormID) -> Bool {
            false
        }

        @discardableResult
        func spawnStuckProjectile(_ arrow: StuckProjectile) -> ReferenceKey? {
            nil
        }

        func removeStuckProjectile(_ key: ReferenceKey) {}
        func residentProjectileCells() -> Set<CellSceneLocation> {
            []
        }

        @discardableResult
        func raiseArcheryEvent(_ name: String) -> Bool {
            false
        }

        func writeArcheryVariable(_ value: BehaviorVariableValue, named name: String) {}
    }

    /// Everything the chain runs over, built once out of the install.
    @MainActor
    private struct Session {
        let spell: ResolvedSpell
        let values: ActorValueRuntime
        let holder: ActorValueHolder
        let caster: CasterRuntime
        let projectiles: ProjectileRuntime
        let world: AcceptanceWorld
    }

    /// Reads the load order, gives the victim its resistance, and readies the
    /// pinned spell in the caster's right hand.
    @MainActor
    private func session() throws -> Session {
        let root = try #require(Self.dataRoot)
        let file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))
        let index = RecordIndex(
            plugins: ActivePluginFiles.load(root: root, baseFile: file),
            recordTypes: ["MGEF", "SPEL", "SCRL", "EQUP", "PROJ"]
        )
        let magicEffects = MagicEffectStore(index: index)
        let spells = SpellStore(index: index, effects: magicEffects)
        let store = WorldStateStore()
        // Five hundred of everything, regenerating nothing, so a number in this
        // suite is only ever what the cast or the hit moved.
        let values = ActorValueRuntime(
            store: store,
            baselines: ActorValueBaselineResolver(
                fallback: ActorValueBaseline(
                    maximums: ActorValues(repeating: 500),
                    regenPercentPerSecond: .zero
                )
            )
        )
        let holder = ActorValueHolder(
            key: Self.victim, subject: .actor(base: FormID(0x0000_0F01)), cell: nil
        )
        values.setValue(at: ActorValueIndex.resistFire, to: Self.resistFirePoints, on: holder)

        let spell = try #require(
            spells.spells.first { $0.editorID == Self.pinnedSpell },
            "this load order carries no \(Self.pinnedSpell)"
        )
        let spellbook = SpellbookRuntime(
            store: store, spells: spells, equipSlots: EquipSlotStore(index: index)
        )
        spellbook.learn(spell.key, on: .player)
        try spellbook.equip(spell.key, in: .right, on: .player)

        let projectiles = ProjectileRuntime(settings: .synthetic)
        let world = AcceptanceWorld(
            effects: ActiveEffectRuntime(values: values, effects: magicEffects),
            items: ItemDefinitionStore(file: file),
            projectiles: projectiles,
            holder: holder
        )
        projectiles.attach(world: world)
        let caster = CasterRuntime(spellbook: spellbook, values: values)
        caster.attach(world: world)
        return Session(
            spell: spell,
            values: values,
            holder: holder,
            caster: caster,
            projectiles: projectiles,
            world: world
        )
    }

    /// The whole chain, end to end: ready, cast, fly, hit, resist, provoke.
    @Test(.enabled(if: Self.dataRoot != nil))
    @MainActor
    func castingAtAnActorLandsResistanceAdjustedDamage() throws {
        let session = try session()
        let (spell, values, holder) = (session.spell, session.values, session.holder)
        let caster = session.caster

        // Cast: charge through the SPIT charge time, then release.
        let magickaBefore = values.current(of: .player).magicka
        caster.begin(.right, on: .player)
        caster.advance(delta: (spell.data?.chargeTime ?? 0) + 0.1, on: .player)
        let outcome = caster.release(.right, on: .player)
        #expect(outcome.isCast)
        #expect(caster.tally.projectileCount == 1, "the cast put no projectile in the air")

        // Fly: the same fixed step an arrow flies on, until something lands.
        let healthBefore = values.current(of: holder).health
        var traces: [ProjectileTrace] = []
        var elapsed: Float = 0
        while traces.isEmpty, elapsed < 5 {
            traces += session.projectiles.advance(by: 1.0 / 60)
            elapsed += 1.0 / 60
        }
        let trace = try #require(traces.first, "the projectile never resolved")
        #expect(trace.outcome == .hitActor)
        #expect(trace.provokes, "a hostile spell hit must provoke, the way an arrow does")

        // Resist: the health taken off is the adjusted magnitude, not the
        // authored one.
        let report = try #require(trace.spellHit)
        let adjustment = try #require(report.adjustments.first)
        let expectedMultiplier = values.magicDamageMultiplier(
            element: adjustment.resistance, on: holder
        )
        #expect(abs(adjustment.multiplier - expectedMultiplier) < 0.0001)
        #expect(adjustment.multiplier < 1, "40% Resist Fire must reduce the magnitude")
        let taken = healthBefore - values.current(of: holder).health
        #expect(
            abs(taken - adjustment.adjustedMagnitude) < 0.01,
            "took \(taken), expected the adjusted \(adjustment.adjustedMagnitude)"
        )
        #expect(taken < adjustment.baseMagnitude)

        try write(
            spell: spell,
            trace: trace,
            adjustment: adjustment,
            magicka: (magickaBefore, values.current(of: .player).magicka),
            health: (healthBefore, values.current(of: holder).health)
        )
    }

    /// The run summary into a directory under gitignored `logs/`, so a pull
    /// request can link the run rather than describe it. Anchored on the source
    /// file, because a test host's working directory is `/`.
    @MainActor
    private func write(
        spell: ResolvedSpell,
        trace: ProjectileTrace,
        adjustment: SpellMagnitudeAdjustment,
        magicka: (Float, Float),
        health: (Float, Float)
    ) throws {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "logs")
            .appending(path: "spell-delivery-acceptance")
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        let text = """
        19.8 aimed-delivery acceptance, issue #471
        spell:          \(spell.editorID ?? spell.displayName), cost \(spell.cost.cost)
        delivery:       \(spell.data?.delivery.description ?? "unknown")
        caster magicka: \(magicka.0) -> \(magicka.1)
        flight:         \(trace.travelled) units in \(trace.flightTime)s, \(trace.outcome)
        effect:         \(adjustment.name), resisted by \
        \(ActorValueIdentity.description(of: adjustment.resistance ?? -1))
        magnitude:      \(adjustment.baseMagnitude) x \(adjustment.multiplier) \
        = \(adjustment.adjustedMagnitude)
        target health:  \(health.0) -> \(health.1)
        provokes:       \(trace.provokes)

        """
        try text.write(
            to: directory.appending(path: "acceptance.txt"),
            atomically: true,
            encoding: .utf8
        )
    }
}
