// Dead and disabled for a reference that may be loaded or not.

import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyQuestsInterface
import OpenSkyWorldState
import Testing

@MainActor
struct QuestReferenceStateTests {
    private static let stranger = ReferenceKey.plugin(name: "base.esm", objectID: 0x999)

    /// Without a persistent index, a reference outside the loaded area reads as
    /// alive and enabled.
    @Test func anUnloadedReferenceWithoutAPersistentIndexIsAliveAndEnabled() {
        let search = QuestReferenceSearch(
            references: RuntimeReferenceIndex(entries: []), origin: nil,
            context: ConditionContext()
        ) { _ in true }
        let state = search.state(of: Self.stranger)
        #expect(!state.isDead)
        #expect(!state.isDisabled)
    }
}
