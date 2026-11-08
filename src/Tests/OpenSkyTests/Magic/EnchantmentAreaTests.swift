// A weapon enchantment's area entries reach the actors near the contact point,
// the same way a spell impact's do. Records are synthetic (`EnchantmentRuntimeFixture`).

import Foundation
@testable import OpenSkyActorsInterface
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyMagic
@testable import OpenSkyMagicInterface
import OpenSkyPhysics
import simd
import Testing

@MainActor
struct EnchantmentAreaTests {
    private static func holder(_ objectID: UInt32) -> ActorValueHolder {
        ActorValueHolder(
            key: .plugin(
                name: EnchantmentRuntimeFixture.pluginName.lowercased(),
                objectID: objectID
            ),
            subject: .player
        )
    }

    private let struck = EnchantmentRuntimeFixture.target
    private let nearby = Self.holder(0x1001)
    private let distant = Self.holder(0x1002)

    /// The struck actor at the origin, one actor beside it, one far away.
    private var candidates: [MeleeTarget] {
        [
            MeleeTarget(key: struck.key, feet: .zero),
            MeleeTarget(key: nearby.key, feet: SIMD3(100, 0, 0)),
            MeleeTarget(key: distant.key, feet: SIMD3(5000, 0, 0))
        ]
    }

    @discardableResult
    private func strike(_ item: UInt32, in world: inout EnchantmentRuntimeFixture.World) throws
        -> WeaponEnchantmentReport
    {
        let hit = try WeaponEnchantmentHit(
            profile: world.profile(of: item),
            attacker: .player,
            struck: struck.key,
            at: SIMD3(0, 0, 60),
            candidates: candidates
        )
        let holders = [struck, nearby, distant].reduce(into: [:]) { $0[$1.key] = $1 }
        return WeaponEnchantmentApplication.apply(
            hit, owner: .player, holders: holders, using: &world.effects
        )
    }

    private func health(
        of holder: ActorValueHolder,
        in world: EnchantmentRuntimeFixture.World
    ) -> Float {
        world.effects.values.current(of: holder).health
    }

    @Test func anAreaEntryReachesTheActorBesideTheStruckOne() throws {
        var world = try EnchantmentRuntimeFixture.world()
        let report = try strike(EnchantmentRuntimeFixture.burstBlade, in: &world)

        let point = EnchantmentRuntimeFixture.bladeDamage
        let area = EnchantmentRuntimeFixture.burstDamage
        #expect(report.didFire)
        #expect(health(of: struck, in: world) == 100 - point - area)
        #expect(health(of: nearby, in: world) == 100 - area)
        #expect(health(of: distant, in: world) == 100)
        // One swing spends one use, however many actors it reached.
        #expect(report.charge.usesRemaining == EnchantmentRuntimeFixture.bladeUses - 1)
    }

    @Test func aPointEnchantmentReachesOnlyTheStruckActor() throws {
        var world = try EnchantmentRuntimeFixture.world()
        try strike(EnchantmentRuntimeFixture.enchantedBlade, in: &world)

        #expect(health(of: struck, in: world) == 100 - EnchantmentRuntimeFixture.bladeDamage)
        #expect(health(of: nearby, in: world) == 100)
    }
}
