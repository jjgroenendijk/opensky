// The wired session the M20 acceptance drives: a real `GameViewController`
// with the four progression coordinators over the synthetic `PerkRuntimeFixture`
// load order, with no renderer, window or game data. The panel reaches the
// coordinators through the controller's own `ProgressionControlProviding`.

import AppKit
@testable import OpenSky
import OpenSkyActors
import OpenSkyActorsTesting
@testable import OpenSkyProgression
import OpenSkyProgressionTesting
@testable import OpenSkyWorld
import Testing

@MainActor
enum ProgressionPanelFixture {
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
        controller.actorValues.wire(baselines: ActorValueBaselineFixture.flat())
        let values = try #require(controller.actorValues.runtime)
        controller.perks.wire(
            PerkRuntime(store: controller.worldState, perks: perks, conditionRegistry: .standard),
            baselines: nil,
            pluginName: PerkRuntimeFixture.pluginName
        )
        controller.progression.wireSkills(values: values, information: information)
        controller.progression.wireLeveling(
            values: values, perkStore: perks, information: information
        )
        return controller
    }
}
