// The `Mod Skill Use` entry point over a perk an active effect grants, the shape of
// the Guardian Stones and the Rested spells, and the three skill-use conditions.

import OpenSkyConditions
import OpenSkyFeaturesTesting
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyProgression
import OpenSkyProgressionInterface
@testable import OpenSkyWorldState
import Testing

@MainActor
struct SkillUseMultiplierTests {
    private let stone = PerkRuntimeFixture.key(PerkRuntimeFixture.Perk.skillUse)
    private let oneHanded = PerkRuntimeFixture.oneHandedIndex

    private static var registry: ConditionFunctionRegistry {
        var registry = ConditionFunctionRegistry.empty
        ConditionFunctions.installSkillUsage(&registry)
        return registry
    }

    private func coordinator(world: FakeProgressionWorld) throws -> PerkCoordinator {
        let index = try PerkRuntimeFixture.index()
        let coordinator = PerkCoordinator()
        coordinator.attach(world: world)
        coordinator.wire(
            PerkRuntime(
                store: WorldStateStore(),
                perks: PerkRuntimeFixture.perkStore(index: index),
                conditionRegistry: Self.registry
            ),
            baselines: nil,
            pluginName: PerkRuntimeFixture.pluginName
        )
        return coordinator
    }

    @Test func anEffectPerkMultipliesOnlyItsOwnSkill() throws {
        let world = FakeProgressionWorld()
        let coordinator = try coordinator(world: world)
        let usage = SkillUsageConditionResolution(skill: oneHanded)

        #expect(coordinator.skillUseMultiplier(usage) == 1)

        world.effectPerks = [stone]
        #expect(abs(coordinator.skillUseMultiplier(usage) - 1.2) < 0.0001)
        #expect(coordinator
            .skillUseMultiplier(SkillUsageConditionResolution(skill: oneHanded + 1)) == 1)

        world.effectPerks = []
        #expect(coordinator.skillUseMultiplier(usage) == 1)
    }

    @Test func theConditionsFailOutsideASkillUse() {
        let context = ConditionContext()
        for index: UInt16 in [681, 692] {
            #expect(value(index, parameter: 0, context: context) ==
                .failure(.unavailableData(.skillUsage)))
        }
    }

    @Test func theConditionsReadTheUseBeingCredited() {
        var context = ConditionContext()
        context.skillUsage = SkillUsageConditionResolution(skill: 9, action: .bash)

        #expect(value(681, parameter: 9, context: context) == .success(1))
        #expect(value(681, parameter: 10, context: context) == .success(0))
        #expect(value(692, parameter: 2, context: context) == .success(1))
        #expect(value(692, parameter: 0, context: context) == .success(0))
    }

    private func value(
        _ index: UInt16, parameter: UInt32, context: ConditionContext
    ) -> Result<Float, ConditionFailure>? {
        guard let function = Self.registry[index] else { return nil }
        var call = ConditionCall(
            condition: Condition(probingFunction: index, parameter1: parameter), context: context
        )
        return function.body(&call)
    }
}
