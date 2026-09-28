// The wired session the M20 acceptance drives (issue #500, roadmap item 20.7).
//
// A real `GameViewController` with the four progression runtimes attached over
// the synthetic `PerkRuntimeFixture` load order — no renderer, no window and no
// game data. That is what makes this suite acceptance evidence rather than a
// second mock: the panel reaches `GameViewController`'s own
// `ProgressionControlProviding` conformance, which reaches
// `SkillAdvancementRuntime`, `PlayerLevelRuntime` and `PerkRuntime` exactly as
// a session does.

import AppKit
@testable import opensky

@MainActor
enum M20Fixture {
    /// One-handed, the actor value the fixture AVIF record describes.
    static let skill = PerkRuntimeFixture.oneHandedIndex
    /// The box granting `DamageRank1`, which is the first real perk of the
    /// fixture tree.
    static let damageNode: UInt32 = 1
    /// The box granting `ShieldWall`, a child of that one.
    static let blockingNode: UInt32 = 2

    /// A controller with skills, perks and character leveling wired over the
    /// fixture load order.
    static func controller() throws -> GameViewController {
        let controller = GameViewController()
        let index = try PerkRuntimeFixture.index()
        let information = PerkRuntimeFixture.informationStore(index: index)
        let perks = PerkRuntimeFixture.perkStore(index: index)
        let values = PerkRuntimeFixture.values(store: controller.worldState)

        controller.actorValues.runtime = values
        controller.perks.runtime = PerkRuntime(store: controller.worldState, perks: perks)
        controller.perks.pluginName = PerkRuntimeFixture.pluginName

        let leveling = PlayerLevelRuntime(values: values)
        controller.progression.runtime = leveling
        controller.progression.trees = PerkTreeIndex(information: information, perks: perks)
        controller.progression.information = information

        var advancement = SkillAdvancementRuntime(
            values: values,
            parameters: SkillUseParameterSource(store: information)
        )
        advancement.leveling = leveling
        controller.skills.runtime = advancement
        return controller
    }
}
