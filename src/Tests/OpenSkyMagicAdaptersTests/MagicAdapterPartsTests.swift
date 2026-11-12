// The parts the magic adapters hand their work to read the same host.

import OpenSkyFormatsESM
@testable import OpenSkyMagicAdapters
@testable import OpenSkyMagicInterface
import OpenSkySessionTesting
import Testing

@MainActor
struct MagicAdapterPartsTests {
    private let host = MagicHost()

    @Test func thePartsReadTheAdaptersHost() {
        let adapter = MagicWorldAdapter(game: host)
        #expect(adapter.sessions.game === host)
        #expect(adapter.frames.game === host)
    }

    @Test func aRuneWithoutAProjectileSetsNothingOff() {
        let explosions = host.fakeCombat.explosions
        let payload = SpellPayload(
            spell: .plugin(name: "base.esm", objectID: 0x600), sourcePlugin: "base.esm",
            caster: .player,
            entries: [], isHostile: true, ignoresResistance: false, projectile: nil, name: "Rune"
        )
        MagicWorldAdapter(game: host).spellDelivery.detonateRune(payload, at: .zero)
        #expect(explosions.detonateCalls.isEmpty)
    }
}
