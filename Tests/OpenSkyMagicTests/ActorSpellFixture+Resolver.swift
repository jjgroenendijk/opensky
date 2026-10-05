// The spell baseline resolver over `ActorSpellFixture` records.

import FeaturesTesting
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyMagic

extension ActorSpellFixture {
    static func resolver(
        npcs: [ActorBase],
        races: [Race] = [],
        leveledSpells: [LeveledList] = []
    ) -> ActorSpellBaselineResolver {
        ActorSpellBaselineResolver(
            templates: ActorTemplateResolver(
                actors: Dictionary(uniqueKeysWithValues: npcs.map { ($0.formID.rawValue, $0) }),
                leveledActors: [:],
                leveledSpells: Dictionary(
                    uniqueKeysWithValues: leveledSpells.map { ($0.formID.rawValue, $0) }
                )
            ),
            races: Dictionary(uniqueKeysWithValues: races.map { ($0.formID.rawValue, $0) })
        )
    }
}
