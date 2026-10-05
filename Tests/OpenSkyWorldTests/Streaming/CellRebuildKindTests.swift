// Which world-state writes rebuild a cell. A quest start, a said line, and a
// scene phase change write only kinds no cell build reads, so they rebuild
// nothing. The kinds a cell build does read still rebuild.

@testable import OpenSkyDialogueInterface
@testable import OpenSkyInventoryInterface
@testable import OpenSkyQuestsInterface
@testable import OpenSkyWorld
@testable import OpenSkyWorldState
import Testing

struct CellRebuildKindTests {
    @Test
    func questDialogueAndSceneWritesRebuildNoCell() {
        let kinds: [WorldStateComponentKind] = [
            .quest, .questAliases, .storyManager, .dialogue, .dialogueBranch, .scene
        ]

        #expect(kinds.filter(\.affectsCellBuild).isEmpty)
    }

    @Test
    func kindsTheCellBuildReadsStillRebuild() {
        let kinds: [WorldStateComponentKind] = [
            .enableState, .transform, .deletion, .spawn, .inventory, .actorPresentation
        ]

        #expect(kinds.filter { !$0.affectsCellBuild }.isEmpty)
    }
}
