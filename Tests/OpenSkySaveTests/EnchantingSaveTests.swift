// ENCK chunk: the known base enchantments and every made enchantment come back on
// the player with their ids, names, charge, and powers.

import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyMagicInterface
@testable import OpenSkySave
import OpenSkySaveFixtures
@testable import OpenSkyWorldState
import Testing

@MainActor
struct EnchantingSaveTests {
    private static let fire = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x045C2A)
    private static let health = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x0493AA)

    @Test func knownAndMadeEnchantmentsSurvive() throws {
        let (once, sword) = EnchantingState(known: [Self.health, Self.fire]).making(
            MadeEnchantment(
                bases: [Self.fire], powers: [1.25], capacity: 3000, costPerUse: 23.7,
                name: "Fire Damage"
            )
        )
        let (state, ring) = once.making(MadeEnchantment(
            bases: [Self.health, Self.fire], powers: [0.5, 0.25], capacity: 0, costPerUse: 0,
            name: "Fortify Health + Fire"
        ))
        let snapshot = OpenSkySaveFixture.snapshot(
            [
                OpenSkySaveFixture.entry(
                    key: .player, cell: OpenSkySaveFixture.whiterun, components: [state.erased]
                )
            ],
            bystanderCell: OpenSkySaveFixture.riverwood
        )
        let data = OpenSkySaveFixture.encode(snapshot)
        #expect(data.range(of: Data("ENCK".utf8)) != nil)
        let file = try OpenSkySaveDecoder.decode(data)
        #expect(file.snapshot == snapshot)
        let restored = try #require(file.snapshot[.player]?.component(EnchantingState.self))
        #expect(restored.known == [Self.fire, Self.health].sorted())
        #expect(sword.rawValue == EnchantingState.firstMadeID)
        #expect(restored.made[ring]?.powers == [0.5, 0.25])
        #expect(restored.made[sword]?.capacity == 3000)
    }
}
