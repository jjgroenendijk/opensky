// The archetype rules over synthetic MGEF records: what each archetype plans to,
// what it forces on an actor, and what it asks the world to do. Semantics: the
// Creation Kit wiki Magic Effect page, cited at `MagicArchetypeRule`.

import OpenSkyActorsInterface
import OpenSkyConditions
import OpenSkyFeaturesTesting
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyMagic
@testable import OpenSkyMagicInterface
import OpenSkyProgressionInterface
import Testing

@MainActor
struct MagicArchetypeTests {
    private typealias Archetype = ActiveEffectFixture.Archetype

    /// One world per suite instance, which the cloak tests configure.
    private let world = FakeMagicWorld()

    private static func store() throws -> MagicEffectStore {
        let file = try ActiveEffectFixture.plugin(
            records: ActiveEffectFixture.effectRecords + ActiveEffectFixture.archetypeRecords
        )
        return MagicEffectStore(plugins: [(ActiveEffectFixture.pluginName, file)])
    }

    private func makeCoordinator() throws -> MagicCoordinator {
        var data = MagicSessionData()
        data.effects = try MagicEffectsData(
            values: FixedActorValues(),
            store: Self.store(),
            pluginName: ActiveEffectFixture.pluginName,
            conditionRegistry: ConditionFunctionRegistry()
        )
        return MagicCoordinator(world: world, data: data)
    }

    private static func entry(_ formID: UInt32, magnitude: Float, duration: UInt32 = 0)
        -> MagicItemEffect
    {
        MagicItemEffect(
            effect: FormID(formID), magnitude: magnitude, area: 0, duration: duration,
            conditions: ConditionList()
        )
    }

    @discardableResult
    private static func cast(
        _ formID: UInt32,
        magnitude: Float,
        duration: UInt32 = 0,
        on coordinator: MagicCoordinator
    ) -> [ActiveEffect] {
        coordinator.withEffects { runtime in
            runtime.apply(
                [entry(formID, magnitude: magnitude, duration: duration)],
                fromPlugin: ActiveEffectFixture.pluginName,
                source: ActiveEffectSource(
                    kind: .spell,
                    record: .plugin(name: "base.esm", objectID: 0x600)
                ),
                caster: .player,
                on: .player
            )
        } ?? []
    }

    private static func plan(_ formID: UInt32, magnitude: Float, duration: UInt32)
        throws -> MagicEffectPlanner.Outcome
    {
        let effect = try #require(store().effect(
            ResolvedFormID(plugin: ActiveEffectFixture.pluginName, objectID: formID)
        ))
        return MagicEffectPlanner.plan(
            effect: effect, entry: entry(formID, magnitude: magnitude, duration: duration)
        )
    }

    // MARK: - Rules and planning

    @Test func everyRuleNamesItsArchetypeFamily() {
        #expect(MagicArchetypeRule.rule(for: .script) == .carrier)
        #expect(MagicArchetypeRule.rule(for: .absorb) == .absorb)
        #expect(MagicArchetypeRule.rule(for: .calm) == .influence(.calm))
        #expect(MagicArchetypeRule.rule(for: .cureDisease) == .dispel(.disease))
        #expect(MagicArchetypeRule.rule(for: .cloak) == .world(.cloak))
        #expect(MagicArchetypeRule.rule(for: .slowTime) == .world(.slowTime))
        #expect(MagicArchetypeRule.rule(for: .invisibility) == .heldFlag(actorValue: 54))
        #expect(MagicArchetypeRule.rule(for: .summonCreature) == .world(.summon))
        #expect(MagicArchetypeRule.rule(for: .light) == .world(.light))
        #expect(MagicArchetypeRule.rule(for: .werewolf) == .world(.changeRace))
        #expect(MagicArchetypeRule.rule(for: .vampireLord) == .world(.changeRace))
        #expect(MagicArchetypeRule.rule(for: .lock) == .carrier)
        #expect(MagicArchetypeRule.rule(for: .valueAndParts) == .valueAndParts)
        #expect(MagicArchetypeRule.rule(for: .unknown13) == nil)
        #expect(MagicArchetypeRule.rule(for: .banish)?.capsTargetLevel == true)
        #expect(MagicArchetypeRule.rule(for: .detectLife)?.actsOnce == true)
        #expect(MagicArchetypeRule.rule(for: .light)?.needsDuration == true)
        #expect(MagicArchetypeRule.rule(for: .calm)?.capsTargetLevel == true)
        #expect(MagicArchetypeRule.rule(for: .paralysis)?.capsTargetLevel == false)
    }

    /// Invisibility holds its actor value at 1, never at -1, whatever the flags say.
    @Test func aHeldFlagPlansAsAPositiveHeldValue() throws {
        let outcome = try Self.plan(Archetype.invisibility, magnitude: 0, duration: 30)
        guard case let .apply(application) = outcome else {
            Issue.record("expected an application, got \(outcome)")
            return
        }
        #expect(application.mode == .modifier)
        #expect(!application.isDetrimental)
        #expect(application.values.map(\.index) == [54])
        #expect(application.values.map(\.magnitude) == [1])
    }

    /// An archetype that only acts while it runs does nothing without a duration.
    @Test func anInfluenceWithNoDurationIsCounted() throws {
        let outcome = try Self.plan(Archetype.calm, magnitude: 10, duration: 0)
        #expect(outcome == .skip(.needsDuration(.calm)))
    }

    @Test func paralysisWithoutRecoverIsCounted() throws {
        let file = try ActiveEffectFixture.plugin(records: [
            ActiveEffectFixture.magicEffect(
                formID: 0x50, editorID: "LoosePara", name: "Loose",
                data: ActiveEffectFixture.data(archetype: 21, primaryValue: 53)
            )
        ])
        let store = MagicEffectStore(plugins: [(ActiveEffectFixture.pluginName, file)])
        let effect = try #require(store.effect(
            ResolvedFormID(plugin: ActiveEffectFixture.pluginName, objectID: 0x50)
        ))
        let outcome = MagicEffectPlanner.plan(
            effect: effect, entry: Self.entry(0x50, magnitude: 1, duration: 5)
        )
        #expect(outcome == .skip(.needsRecover(.paralysis)))
    }

    // MARK: - Influence

    @Test func calmUpToItsLevelCalmsTheTarget() throws {
        let coordinator = try makeCoordinator()
        Self.cast(Archetype.calm, magnitude: 9, duration: 30, on: coordinator)
        #expect(coordinator.influence(of: .player).isCalmed)
        #expect(coordinator.influence(of: .player).refusesCombat)
    }

    /// UESP "Skyrim:Pickpocket": Harmony, a calm cast from self over an area, makes its
    /// targets forget a catch. A calm without an area, or on its own caster, does not.
    @Test func aCalmFromAroundItsCasterForgetsAPickpocketCatch() throws {
        let coordinator = try makeCoordinator()
        let npc = ReferenceKey.plugin(name: "base.esm", objectID: 0x700)
        for (area, caster) in [(UInt32(0), npc), (20, .player), (20, npc)] {
            _ = coordinator.withEffects { runtime in
                runtime.apply(
                    [MagicItemEffect(
                        effect: FormID(Archetype.calm), magnitude: 9, area: area, duration: 30,
                        conditions: ConditionList()
                    )],
                    fromPlugin: ActiveEffectFixture.pluginName,
                    source: ActiveEffectSource(kind: .spell, record: npc),
                    caster: caster,
                    on: .player
                )
            }
        }
        #expect(world.forgottenCatches == [.player])
    }

    /// "up to level <MAG>": a level-1 target resists a magnitude below 1.
    @Test func calmAboveItsLevelCapIsRefused() throws {
        let coordinator = try makeCoordinator()
        Self.cast(Archetype.calm, magnitude: 0.5, duration: 30, on: coordinator)
        #expect(coordinator.influence(of: .player).isNone)
        #expect(coordinator.effects?.tally.skips[.aboveLevelCap(.calm)] == 1)
    }

    @Test func turnUndeadNeedsTheUndeadKeyword() throws {
        let coordinator = try makeCoordinator()
        Self.cast(Archetype.turnUndead, magnitude: 20, duration: 30, on: coordinator)
        #expect(!coordinator.influence(of: .player).isFrightened)
        #expect(coordinator.effects?.tally.skips[.notUndead] == 1)

        world.undead = [.player]
        Self.cast(Archetype.turnUndead, magnitude: 20, duration: 30, on: coordinator)
        #expect(coordinator.influence(of: .player).flees)
    }

    @Test func rallyOutweighsFear() throws {
        let coordinator = try makeCoordinator()
        Self.cast(Archetype.demoralize, magnitude: 20, duration: 30, on: coordinator)
        #expect(coordinator.influence(of: .player).flees)
        Self.cast(Archetype.rally, magnitude: 20, duration: 30, on: coordinator)
        #expect(!coordinator.influence(of: .player).flees)
    }

    // MARK: - Dispels

    @Test func dispelRemovesTimedEffects() throws {
        let coordinator = try makeCoordinator()
        Self.cast(Archetype.frenzy, magnitude: 20, duration: 30, on: coordinator)
        #expect(coordinator.influence(of: .player).isFrenzied)
        Self.cast(Archetype.dispel, magnitude: 1, on: coordinator)
        #expect(coordinator.effects?.active(on: .player).isEmpty == true)
    }

    @Test func cureParalysisRemovesOnlyParalysis() throws {
        let coordinator = try makeCoordinator()
        Self.cast(ActiveEffectFixture.paralyze, magnitude: 1, duration: 10, on: coordinator)
        Self.cast(Archetype.frenzy, magnitude: 20, duration: 30, on: coordinator)
        #expect(coordinator.influence(of: .player).isParalysed)
        Self.cast(Archetype.cureParalysis, magnitude: 1, on: coordinator)
        #expect(!coordinator.influence(of: .player).isParalysed)
        #expect(coordinator.influence(of: .player).isFrenzied)
    }

    /// The Script archetype "has no effect other than any Papyrus Scripts", so it
    /// is stored for `HasMagicEffect` and moves nothing.
    @Test func aScriptEffectIsStoredAndDoesNothingElse() throws {
        let coordinator = try makeCoordinator()
        let stored = Self.cast(Archetype.script, magnitude: 0, duration: 10, on: coordinator)
        #expect(stored.count == 1)
        #expect(coordinator.influence(of: .player).isNone)
        #expect(coordinator.effects?.worldActions.isEmpty == true)
    }

    // MARK: - World actions

    /// A running stagger blocks the next one until it ends.
    @Test func staggerReachesTheWorldOncePerDuration() throws {
        let coordinator = try makeCoordinator()
        Self.cast(Archetype.stagger, magnitude: 0.5, duration: 2, on: coordinator)
        Self.cast(Archetype.stagger, magnitude: 0.5, duration: 2, on: coordinator)
        #expect(coordinator.takeCommands() == [.stagger(.player, magnitude: 0.5)])
    }

    @Test func spawnHazardPlacesTheAssociatedHazard() throws {
        let coordinator = try makeCoordinator()
        Self.cast(Archetype.spawnHazard, magnitude: 10, on: coordinator)
        let hazard = ReferenceKey(resolved: ResolvedFormID(
            plugin: ActiveEffectFixture.pluginName, objectID: Archetype.hazard
        ))
        #expect(coordinator.takeCommands() == [.spawnHazard(hazard, at: .player)])
    }

    /// "You may only have one cloak spell active at any given time."
    @Test func aSecondCloakReplacesTheFirst() throws {
        let coordinator = try makeCoordinator()
        Self.cast(Archetype.cloak, magnitude: 200, duration: 60, on: coordinator)
        Self.cast(Archetype.cloak, magnitude: 300, duration: 60, on: coordinator)
        let cloaks = coordinator.effects?.active(on: .player) ?? []
        #expect(cloaks.map(\.peakMagnitude) == [300])
    }

    // MARK: - Slow Time

    /// UESP "Skyrim:Slow Time": the world runs at the magnitude, the player at 70%.
    @Test func slowTimeSlowsTheWorldMoreThanThePlayer() throws {
        let coordinator = try makeCoordinator()
        #expect(coordinator.timeScales == .normal)
        Self.cast(Archetype.slowTime, magnitude: 0.3, duration: 8, on: coordinator)
        #expect(coordinator.timeScales == MagicTimeScales(world: 0.3, player: 0.7))
    }

    /// Quick Reflexes sets entry point 70 to 1: the player is not slowed at all.
    @Test func entryPoint70SetsThePlayersShare() throws {
        let coordinator = try makeCoordinator()
        world.perkValues[.modPlayerMagicSlowdown] = 1
        Self.cast(Archetype.slowTime, magnitude: 0.05, duration: 1, on: coordinator)
        #expect(coordinator.timeScales == MagicTimeScales(world: 0.05, player: 1))
    }

    @Test func slowTimeEffectsStack() {
        let scales = SlowTimeRule.scales([(world: 0.3, player: 0.7), (world: 0.5, player: 1)])
        #expect(abs(scales.world - 0.15) < 1e-6)
        #expect(abs(scales.player - 0.7) < 1e-6)
        let stopped = SlowTimeRule.scales([(world: 0, player: 0)])
        #expect(stopped.world == SlowTimeRule.minimumWorldShare)
    }

    /// The player's effects run on the player's clock, so an 8 s Slow Time ends after
    /// 8 s of the player's time, not 8 s of the slowed world's.
    @Test func slowTimeEndsOnThePlayersClock() throws {
        let coordinator = try makeCoordinator()
        Self.cast(Archetype.slowTime, magnitude: 0.3, duration: 8, on: coordinator)
        // 4 s of world time in small frames: 9.3 s on the player's clock.
        for _ in 0 ..< 200 {
            _ = coordinator.advanceEffects(delta: 0.02)
        }
        #expect(coordinator.timeScales == .normal)
        #expect(coordinator.effects?.active(on: .player).isEmpty == true)
    }

    // MARK: - Readout

    @Test func theReadoutNamesAnArchetypeWithNoActorValue() throws {
        let coordinator = try makeCoordinator()
        Self.cast(Archetype.calm, magnitude: 9, duration: 30, on: coordinator)
        let snapshot = coordinator.magicEffectControlSnapshot
        let line = snapshot.playerEffects.first?.line ?? ""
        #expect(line.contains("calm: \(MagicArchetypeRule.influence(.calm).summary)"))
        #expect(line.contains("at magnitude 9.0"))
        #expect(MagicEffectControlReadout.influenceText(for: snapshot).contains("calmed"))
    }
}
