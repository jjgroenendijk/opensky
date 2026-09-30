// The wired session the M20 acceptance drives: a real `GameViewController`
// with the four progression runtimes over the synthetic `PerkRuntimeFixture`
// load order, with no renderer, window or game data. The panel reaches the
// runtimes through the controller's own `ProgressionControlProviding`.

import AppKit
@testable import OpenSky
@testable import OpenSkyProgression
import OpenSkyProgressionTesting
@testable import OpenSkyWorld

@MainActor
enum M20Fixture {
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
        controller.perks.runtime = PerkRuntime(
            store: controller.worldState,
            perks: perks,
            conditionRegistry: .standard
        )
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
