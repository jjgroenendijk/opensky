// The dialogue runtime over the fixture world.

@testable import OpenSkyDialogue
@testable import OpenSkyDialogueInterface
import OpenSkyDialogueTesting
@testable import OpenSkyQuestsInterface
@testable import OpenSkyWorldState

extension DialogueRuntimeFixture {
    /// A runtime over a fresh store, with the speaker placed and the two
    /// quests reading from plugin data.
    @MainActor
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
