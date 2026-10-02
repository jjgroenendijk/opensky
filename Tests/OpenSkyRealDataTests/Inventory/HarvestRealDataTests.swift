// Harvests a real FLOR reference near Whiterun: its produce lands in the player
// inventory, the harvested state survives a save round trip, and a second
// harvest is refused. Run with `make test-real T='HarvestRealDataTests'`.

import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyInventory
@testable import OpenSkyInventoryInterface
@testable import OpenSkySave
import OpenSkySaveFixtures
@testable import OpenSkyWorld
@testable import OpenSkyWorldInterface
@testable import OpenSkyWorldState
import OpenSkyWorldTesting
import TagsTesting
import Testing

@Suite(.tags(.gpu))
@MainActor
struct HarvestRealDataTests {
    private static let sweptRadius: Int32 = 2

    @Test(.enabled(if: RealDataEnvironment.canRender))
    func aRealFloraHarvestGrantsItsIngredientAndSurvivesASave() throws {
        let cells = try WhiterunCellSweep()
        let baselines = InventoryBaselineResolver.build(from: cells.file)
        let found = try #require(
            Self.firstFlora(in: cells.scenes(radius: Self.sweptRadius), items: baselines.items)
        )

        let store = WorldStateStore()
        let references = FakeWorldReferences(
            entries: found.scene.references.sortedEntries(), cell: found.scene.location
        )
        let runtime = WorldItemRuntime(
            inventory: InventoryRuntime(store: store, baselines: baselines),
            references: references
        )
        let outcome = try runtime.harvest(found.flora)
        let ingredient = try #require(found.flora.produce?.ingredient)
        #expect(outcome.granted == [InventoryStack(item: ingredient, count: 1)])
        #expect(runtime.inventory.count(of: ingredient, in: .player) == 1)
        #expect(runtime.labelled(found.flora).actionLabel == InteractionAction.harvestedLabel)

        let saved = OpenSkySaveFixture.encode(store.snapshot())
        let reloaded = WorldStateStore()
        try reloaded.restore(from: OpenSkySaveDecoder.decode(saved).snapshot)
        let after = WorldItemRuntime(
            inventory: InventoryRuntime(store: reloaded, baselines: baselines),
            references: references
        )
        #expect(after.isHarvested(found.flora))
        #expect(after.inventory.count(of: ingredient, in: .player) == 1)
        #expect(throws: HarvestError.alreadyHarvested(found.flora.reference)) {
            try after.harvest(found.flora)
        }
    }

    /// The first FLOR reference whose produce is an ingredient the item index knows.
    private static func firstFlora(
        in scenes: [CellScene],
        items: ItemDefinitionStore
    ) -> (scene: CellScene, flora: PlacedInteraction)? {
        for scene in scenes {
            let flora = scene.interactions.values
                .sorted { $0.reference.rawValue < $1.reference.rawValue }
                .first { interaction in
                    interaction.action == .harvest
                        && interaction.produce?.ingredient.flatMap(items.definition)?
                        .family == .ingredient
                }
            if let flora {
                return (scene, flora)
            }
        }
        return nil
    }
}
