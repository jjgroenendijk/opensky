// One impact sets off one explosion: only the spell's main effect is marked to give it.

@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
import OpenSkyGameData
@testable import OpenSkyMagicInterface
import Testing

struct SpellHitEffectLinksTests {
    @Test func onlyTheCostliestEffectGivesTheExplosion() throws {
        let file = try SpellStoreFixture.plugin(records: [
            SpellStoreFixture.magicEffect(formID: 0x800, editorID: "Fire", name: "Fire", cost: 5),
            SpellStoreFixture.magicEffect(formID: 0x801, editorID: "Burst", name: "Burst", cost: 1),
            SpellStoreFixture.magicEffect(formID: 0x802, editorID: "Ash", name: "Ash", cost: 5)
        ])
        let store = MagicEffectStore(plugins: [("Base.esm", file)])
        let payload = SpellPayload(
            spell: .player, sourcePlugin: "Base.esm", caster: .player,
            entries: [0x801, 0x800, 0x802].map {
                MagicItemEffect(effect: FormID($0), magnitude: 40, area: 15, duration: 0)
            },
            isHostile: true, ignoresResistance: false, projectile: nil, name: "Fireball"
        )

        let links = store.hitEffectLinks(of: payload)

        #expect(links.map(\SpellHitEffectLinks.isMain) == [false, true, false])
        #expect(links.allSatisfy { $0.explosion != nil && $0.area > 0 })
    }
}
