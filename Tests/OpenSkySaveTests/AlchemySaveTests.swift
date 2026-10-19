// CPOT, INGK, and WPSN chunks: brewed potions, known ingredient effects, the
// poison on a weapon, and the day the player left each cell come back on the player.

import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyInventoryInterface
@testable import OpenSkySave
import OpenSkySaveFixtures
@testable import OpenSkyWorldState
import Testing

@MainActor
struct AlchemySaveTests {
    private static let ingredient = FormID(0x0006_BC02)
    private static let weapon = FormID(0x0001_2EB7)
    private static let poison = FormID(0x0003_EB2E)

    private func snapshot(_ components: [WorldStateComponentValue]) -> WorldStateSnapshot {
        OpenSkySaveFixture.snapshot(
            [
                OpenSkySaveFixture.entry(
                    key: .player, cell: OpenSkySaveFixture.whiterun, components: components
                )
            ],
            bystanderCell: OpenSkySaveFixture.riverwood
        )
    }

    private func roundTrip(
        _ components: [WorldStateComponentValue], chunk: String
    ) throws -> ReferenceStateDelta? {
        let data = OpenSkySaveFixture.encode(snapshot(components))
        #expect(data.range(of: Data(chunk.utf8)) != nil)
        let file = try OpenSkySaveDecoder.decode(data)
        #expect(file.snapshot == snapshot(components))
        return file.snapshot[.player]
    }

    @Test func brewedPotionsKeepTheirIDsNamesAndEffects() throws {
        let effects = [
            CreatedPotionEffect(effect: FormID(0x0003_EB15), magnitude: 9, area: 0, duration: 0),
            CreatedPotionEffect(effect: FormID(0x0003_EB16), magnitude: 4, area: 5, duration: 30)
        ]
        let (once, _) = CreatedPotionState().adding(
            name: "Potion of Restore Health", isPoison: false, value: 25, effects: effects
        )
        let (state, poison) = once.adding(
            name: "Poison of Damage Health", isPoison: true, value: 40, effects: [effects[1]]
        )
        let restored = try roundTrip([state.erased], chunk: "CPOT")
        #expect(restored?.component(CreatedPotionState.self) == state)
        #expect(poison.id.rawValue == CreatedPotionState.firstObjectID + 1)
    }

    @Test func knownEffectsAndWeaponPoisonsSurvive() throws {
        let knowledge = IngredientKnowledgeState().learning([0, 3], of: Self.ingredient)
        let poisons = WeaponPoisonState()
            .applying(WeaponPoison(poison: Self.poison, doses: 3), to: Self.weapon)
        let data = OpenSkySaveFixture.encode(snapshot([knowledge.erased, poisons.erased]))
        #expect(data.range(of: Data("INGK".utf8)) != nil)
        #expect(data.range(of: Data("WPSN".utf8)) != nil)
        let file = try OpenSkySaveDecoder.decode(data)
        let restored = file.snapshot[.player]
        #expect(restored?.component(IngredientKnowledgeState.self) == knowledge)
        #expect(restored?.component(WeaponPoisonState.self) == poisons)
    }

    @Test func noAlchemyWritesNoChunk() {
        let data = OpenSkySaveFixture.encode(
            OpenSkySaveFixture.snapshot([], bystanderCell: OpenSkySaveFixture.riverwood)
        )
        for chunk in ["CPOT", "INGK", "WPSN"] {
            #expect(data.range(of: Data(chunk.utf8)) == nil)
        }
    }
}
