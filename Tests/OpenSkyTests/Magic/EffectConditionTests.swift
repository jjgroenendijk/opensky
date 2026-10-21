// Conditions on a stored effect: the MGEF's own list decides whether the target
// ever gets the effect, and the entry's list is checked again every second.
// Abilities hold every entry while known. The toggled condition is `IsPC1stPerson`.

import Foundation
@testable import OpenSkyActorsInterface
@testable import OpenSkyConditions
import OpenSkyFeaturesTesting
import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyMagic
@testable import OpenSkyMagicInterface
@testable import OpenSkyWorldState
import Testing

@MainActor
struct EffectConditionTests {
    private static let registry: ConditionFunctionRegistry = {
        var registry = ConditionFunctionRegistry()
        ConditionFunctions.installCamera(&registry)
        ConditionFunctions.installMagic(&registry)
        return registry
    }()

    private func runtime(firstPerson: Bool) throws -> ActiveEffectRuntime {
        var (runtime, _) = try ActiveEffectFixture.runtime(conditionRegistry: Self.registry)
        setFirstPerson(firstPerson, on: &runtime)
        return runtime
    }

    private func setFirstPerson(_ value: Bool, on runtime: inout ActiveEffectRuntime) {
        var camera = CameraConditionResolution()
        camera.playerIsFirstPerson = value
        camera.isAvailable = true
        runtime.conditions.camera = camera
    }

    private func firstPersonList() throws -> ConditionList {
        var list = ConditionList()
        try list.decode(field: ConditionEvaluatorFixture.field(
            comparisonValue: Float(1).bitPattern, functionIndex: 391
        ))
        return list
    }

    private func step(_ runtime: inout ActiveEffectRuntime, seconds: Double) {
        let steps = Int((seconds / ActiveEffectRuntime.fixedStepSeconds).rounded())
        for _ in 0 ..< steps {
            runtime.step(over: [.player])
        }
    }

    /// An `MGEF` condition that fails means the target never gets the effect.
    @Test func aFailingEffectConditionKeepsTheEffectOff() throws {
        var runtime = try runtime(firstPerson: false)
        let stored = ActiveEffectFixture.apply(&runtime, [ActiveEffectFixture.entry(
            ActiveEffectFixture.firstPersonFortify, magnitude: 20, duration: 10
        )])
        #expect(stored.isEmpty)
        #expect(runtime.tally.effectConditionSkipped == 1)

        setFirstPerson(true, on: &runtime)
        let landed = ActiveEffectFixture.apply(&runtime, [ActiveEffectFixture.entry(
            ActiveEffectFixture.firstPersonFortify, magnitude: 20, duration: 10
        )])
        #expect(landed.count == 1)
    }

    /// A failing entry check gives the slot back; a passing one takes it again.
    @Test func aFailingEntryConditionSuspendsTheEffectEachSecond() throws {
        var runtime = try runtime(firstPerson: true)
        let index = ActorValueIndex.resistFire
        let stored = try ActiveEffectFixture.apply(&runtime, [ActiveEffectFixture.entry(
            ActiveEffectFixture.fortifyResistFire,
            magnitude: 20,
            duration: 10,
            conditions: firstPersonList()
        )])
        #expect(stored.count == 1)
        let list = try firstPersonList()
        runtime.entryConditions = { _ in list }
        #expect(runtime.values.entry(at: index, on: .player)?.temporary == 20)

        setFirstPerson(false, on: &runtime)
        step(&runtime, seconds: 1)
        #expect(runtime.active(on: .player).first?.isSuspended == true)
        #expect(runtime.values.entry(at: index, on: .player)?.temporary == 0)

        setFirstPerson(true, on: &runtime)
        step(&runtime, seconds: 1)
        #expect(runtime.active(on: .player).first?.isSuspended == false)
        #expect(runtime.values.entry(at: index, on: .player)?.temporary == 20)
        #expect(runtime.tally.suspended == 1)
        #expect(runtime.tally.resumed == 1)
    }

    /// A constant effect whose entry fails at first is stored suspended, so it
    /// starts acting when the condition passes, as a night-only ability does.
    @Test func aConstantEffectWithAFailingEntryWaitsSuspended() throws {
        var runtime = try runtime(firstPerson: false)
        let list = try firstPersonList()
        let stored = runtime.apply(
            [ActiveEffectFixture.entry(
                ActiveEffectFixture.fortifyResistFire, magnitude: 15, conditions: list
            )],
            fromPlugin: ActiveEffectFixture.pluginName,
            source: ActiveEffectFixture.potionSource,
            isConstant: true,
            on: .player
        )
        runtime.entryConditions = { _ in list }
        #expect(stored.first?.isSuspended == true)
        #expect(runtime.values.value(at: ActorValueIndex.resistFire, on: .player) == 0)

        setFirstPerson(true, on: &runtime)
        step(&runtime, seconds: 1)
        #expect(runtime.values.value(at: ActorValueIndex.resistFire, on: .player) == 15)
    }

    /// An ability's zero-duration entry holds while the spell is known and goes
    /// when it is forgotten.
    @Test func anAbilityHoldsItsZeroDurationEntriesWhileKnown() throws {
        var runtime = try runtime(firstPerson: true)
        let index = try RecordIndex(
            plugins: [(SpellbookFixture.pluginName, SpellbookFixture.plugin())],
            recordTypes: ["MGEF", "SPEL", "SCRL", "EQUP", "PROJ"]
        )
        let spells = SpellStore(index: index)
        let ability = try #require(spells.spell(key: SpellbookFixture.key(
            SpellbookFixture.Spell.resistFire
        )))
        runtime = ActiveEffectRuntime(
            values: runtime.values,
            effects: MagicEffectStore(index: index),
            conditionRegistry: Self.registry
        )

        let report = SpellAbilityApplication.reconcile(
            known: [ability], on: .player, using: &runtime
        )

        #expect(report.storedCount == 2)
        let allConstant = runtime.active(on: .player).allSatisfy(\.isConstant)
        #expect(allConstant)
        #expect(runtime.values.value(at: ActorValueIndex.resistFire, on: .player) == 35)
        let again = SpellAbilityApplication.reconcile(
            known: [ability], on: .player, using: &runtime
        )
        #expect(again == .none)

        SpellAbilityApplication.reconcile(known: [], on: .player, using: &runtime)
        #expect(runtime.values.value(at: ActorValueIndex.resistFire, on: .player) == 0)
    }
}
