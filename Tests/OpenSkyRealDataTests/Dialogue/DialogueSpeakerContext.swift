// The condition context a real-data dialogue suite selects one speaker against:
// its placement and actor state, its and the player's authored factions, its
// voice type, and the form lists. The app's dialogue context supplies the same
// seams to the quest dialogue conditions.

import Foundation
@testable import OpenSkyActorsInterface
@testable import OpenSkyConditions
@testable import OpenSkyDialogueInterface
@testable import OpenSkyFactions
@testable import OpenSkyFactionsInterface
import OpenSkyFeaturesTesting
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyWorld
@testable import OpenSkyWorldState

/// One `Skyrim.esm` NPC_ record and the synthetic placement it is selected
/// through. Selection needs a `ReferenceKey` with a base form, not a loaded cell.
struct DialogueSpeakerContext {
    let base: UInt32
    var reference: UInt32 = 0x000A_0001
    private static let playerBase: UInt32 = 0x0000_0007
    private static let plugin = "Skyrim.esm"

    var speakerKey: ReferenceKey {
        .plugin(name: Self.plugin.lowercased(), objectID: reference)
    }

    @MainActor
    func context(root: GameDataRoot, file: ESMFile) throws -> ConditionContext {
        let localized = try file.pluginHeader().isLocalized
        let templates = ActorTemplateResolver.build(from: file, localized: localized)
        var context = try ConditionContext(
            factions: factionResolution(root: root, file: file, templates: templates),
            references: ConditionEvaluatorFixture.references([
                (formID: reference, base: base)
            ]),
            subject: speakerKey,
            target: .player
        )
        let voice = ActorIdentityRecords(templates: templates, races: [:])
            .voiceType(ofBase: FormID(base))
        context.dialogue = DialogueResolution(voiceTypes: voice.map { [speakerKey: $0] } ?? [:])
        context.data = ConditionDataResolution(
            formLists: FormListStore(plugins: [(Self.plugin, file)]), sourcePlugin: Self.plugin
        )
        let health = ActorValues(health: 100, magicka: 100, stamina: 100)
        context.actors = ActorStateResolution(states: [
            speakerKey: ActorConditionState(current: health, maximums: health)
        ])
        return context
    }

    @MainActor
    private func factionResolution(
        root: GameDataRoot, file: ESMFile, templates: ActorTemplateResolver
    ) -> FactionConditionResolution {
        let factions = FactionStoreLoader.load(root: root, baseFile: file)
        var runtime = FactionRuntime(
            store: WorldStateStore(),
            factions: factions,
            derivation: HostilityDerivation(
                relations: FactionRelationIndex(store: factions),
                relationships: RelationshipStoreLoader.load(root: root, baseFile: file)
            ),
            baselines: ActorFactionBaselineResolver(templates: templates),
            pluginName: Self.plugin
        )
        let holders = [(speakerKey, base), (ReferenceKey.player, Self.playerBase)].map {
            ActorValueHolder(key: $0.0, subject: .actor(base: FormID($0.1)), cell: nil)
        }
        var profiles: [ReferenceKey: ActorSocialProfile] = [:]
        for holder in holders {
            runtime.seed(holder)
            profiles[holder.key] = runtime.profile(of: holder)
        }
        return FactionConditionResolution(
            factions: factions, sourcePlugin: Self.plugin,
            derivation: runtime.derivation, profiles: profiles
        )
    }
}
