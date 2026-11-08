// The dialogue runtime over the fixture world.

@testable public import OpenSkyDialogue
@testable public import OpenSkyDialogueInterface
public import OpenSkyFeaturesTesting
@testable import OpenSkyQuestsInterface
@testable public import OpenSkyWorldState

@MainActor
extension DialogueRuntimeFixture {
    /// A runtime over a fresh store, with the speaker placed and the two
    /// quests reading from plugin data.
    public static func runtime(
        store: WorldStateStore = WorldStateStore(),
        fragments: (any DialogueFragmentDispatching)? = nil
    ) throws -> DialogueRuntime {
        let quests = try questStore()
        return try DialogueRuntime(
            store: store,
            dialogue: dialogueStore(),
            questStates: QuestResolution(defaults: quests),
            context: context(),
            registry: .dialogueTests,
            fragments: fragments
        )
    }
}
