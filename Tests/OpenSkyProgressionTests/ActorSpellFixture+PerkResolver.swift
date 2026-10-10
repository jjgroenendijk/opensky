// The perk baseline resolver over `ActorSpellFixture` records.

import OpenSkyFeaturesTesting
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyProgression

extension ActorSpellFixture {
    /// The perk half of the same template resolution, over the same NPC_
    /// records.
    static func perkResolver(npcs: [ActorBase]) -> ActorPerkBaselineResolver {
        ActorPerkBaselineResolver(
            templates: ActorTemplateResolver(
                actors: Dictionary(uniqueKeysWithValues: npcs.map { ($0.formID.rawValue, $0) }),
                leveledActors: [:]
            )
        )
    }
}
