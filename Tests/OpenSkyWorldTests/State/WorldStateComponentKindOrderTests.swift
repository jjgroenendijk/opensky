import OpenSkyActorsInterface
import OpenSkyCrimeInterface
import OpenSkyDialogueInterface
import OpenSkyFactionsInterface
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyProgressionInterface
import OpenSkyQuestsInterface
import OpenSkyScriptingInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import Testing

/// Iteration, the change journal, and a wholesale reset sort by `order`, so two
/// kinds with one order have no fixed order between them. A new kind goes in this list.
struct WorldStateComponentKindOrderTests {
    private static let declaredKinds: [WorldStateComponentKind] = [
        .enableState, .transform, .activation, .deletion, .inventory, .spawn, .quest,
        .questAliases, .actorValues, .death, .combat, .dialogue, .activeEffects, .spellbook,
        .enchantedItems, .perks, .factions, .relationships, .playerProgress, .crimeLedger,
        .harvest, .lock, .scene, .storyManager, .dialogueBranch, .helpMessages,
        .playerIdentity, .mapMarker, .localMapFog, .actorPresentation, .temperedItems
    ]

    @Test func everyKindHasItsOwnOrder() {
        let byOrder = Dictionary(grouping: Self.declaredKinds, by: \.order)
        let shared = byOrder.values.filter { $0.count > 1 }.map { $0.map(\.rawValue).sorted() }
        #expect(shared.isEmpty, "kinds sharing an order: \(shared)")
    }

    @Test func everyKindHasItsOwnName() {
        #expect(Set(Self.declaredKinds.map(\.rawValue)).count == Self.declaredKinds.count)
    }
}
