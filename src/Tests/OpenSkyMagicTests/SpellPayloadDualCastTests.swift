// What a dual cast changes on a landed spell, and the MGEF flags a landing reads.
// Rules: docs/engine/spellcasting.md#dual-casting, docs/formats/magic-records.md.

import Foundation
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
import OpenSkyGameData
@testable import OpenSkyMagicInterface
import OpenSkyPhysics
import Testing

struct SpellPayloadDualCastTests {
    private static func payload(projectile: FormID? = FormID(0x900)) -> SpellPayload {
        SpellPayload(
            spell: .player, sourcePlugin: "Base.esm", caster: .player,
            entries: [
                MagicItemEffect(effect: FormID(0x800), magnitude: 10, area: 10, duration: 0)
            ],
            isHostile: true, ignoresResistance: false, projectile: projectile, name: "Fireball"
        )
    }

    private static func art(
        projectile: FormID? = nil, explosion: FormID? = nil,
        inherits: DualCastData.InheritScale = []
    ) -> DualCastData.Art {
        DualCastData.Art(
            projectile: projectile, explosion: explosion, effectShader: FormID(0x950),
            hitEffectArt: FormID(0x951), impactDataSet: nil, inheritScale: inherits
        )
    }

    @Test func aSingleCastKeepsItsOwnSizeAndArt() {
        var payload = Self.payload()
        payload.dualCastScale = 1.5
        payload.dualCastArt = Self.art(projectile: FormID(0x901), explosion: FormID(0x902))
        #expect(payload.projectileScale == 1)
        #expect(payload.explosionScale == 1)
        #expect(payload.launchedProjectile == FormID(0x900))
        #expect(payload.explosion(projectileExplosion: FormID(0x903)) == FormID(0x903))
    }

    @Test func aDualCastGrowsByTheScale() {
        var payload = Self.payload()
        payload.dualCastScale = 1.5
        payload = payload.dualCast(payload.entries)
        #expect(payload.isDualCast)
        #expect(payload.projectileScale == 1.5)
        #expect(payload.explosionScale == 1.5)
        #expect(payload.launchedProjectile == FormID(0x900))
    }

    /// A `DUAL` projectile keeps scale 1 without its inherit flag; its explosion inherits.
    @Test func aDualArtReplacesTheLinksAndItsFlagsKeepTheScale() {
        var payload = Self.payload()
        payload.dualCastScale = 2
        payload.dualCastArt = Self.art(
            projectile: FormID(0x901), explosion: FormID(0x902), inherits: .explosion
        )
        payload = payload.dualCast(payload.entries)
        #expect(payload.launchedProjectile == FormID(0x901))
        #expect(payload.explosion(projectileExplosion: FormID(0x903)) == FormID(0x902))
        #expect(payload.projectileScale == 1)
        #expect(payload.explosionScale == 2)
    }

    @Test func aChainExplosionSkipsTheAreaSearch() {
        var payload = Self.payload()
        let bystander = MeleeTarget(
            key: .plugin(name: "Base.esm", objectID: 0x10),
            feet: SIMD3(5, 0, 0)
        )
        let landing: (SIMD3<Float>, ReferenceKey?) = (.zero, nil)
        #expect(SpellHitTargeting.targets(
            of: payload, landing: landing, candidates: [bystander], excluding: .player
        ).count == 1)
        payload.skipsAreaSearch = true
        #expect(SpellHitTargeting.targets(
            of: payload, landing: landing, candidates: [bystander], excluding: .player
        ).isEmpty)
    }

    private static func effect(_ formID: UInt32, flags: MagicEffectFlags) -> Data {
        ESMFixture.record(
            "MGEF", formID: formID,
            data: ESMFixture.field("EDID", ESMFixture.zstring("Effect\(formID)"))
                + ESMFixture.field("DATA", MagicEffectFixture.data(flags: flags))
        )
    }

    @Test func noHitEffectStartsNoShaderOrArt() throws {
        let file = try SpellStoreFixture.plugin(records: [
            Self.effect(0x800, flags: [.hostile, .noHitEffect]),
            Self.effect(0x801, flags: .hostile)
        ])
        let store = MagicEffectStore(plugins: [("Base.esm", file)])
        let payload = SpellPayload(
            spell: .player, sourcePlugin: "Base.esm", caster: .player,
            entries: [0x800, 0x801].map {
                MagicItemEffect(effect: FormID($0), magnitude: 1, area: 0, duration: 0)
            },
            isHostile: true, ignoresResistance: false, projectile: nil, name: "Spark"
        )
        let links = store.hitEffectLinks(of: payload)
        #expect(links.map(\.hitShader).map { $0 == nil } == [true, false])
        #expect(links.map(\.hitEffectArt).map { $0 == nil } == [true, false])
    }
}
