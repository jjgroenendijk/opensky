// A staff casts its enchantment through the hand loop, pays from its charge rather than
// magicka, and is refused once the charge is below one use.

import Foundation
@testable import OpenSkyActors
import OpenSkyFeaturesTesting
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
@testable import OpenSkyMagic
import OpenSkyMagicFixtures
@testable import OpenSkyMagicInterface
@testable import OpenSkyWorldState
import Testing

@MainActor
private final class FakeStaffs: StaffCharging {
    var spell: ResolvedSpell?
    var charge: Float = 0

    func staffSpell(in hand: SpellHand, of _: ActorValueHolder) -> ResolvedSpell? {
        hand == .right ? spell : nil
    }

    func staffCharge(of _: ResolvedSpell, on _: ActorValueHolder) -> Float {
        charge
    }

    func spendStaffCharge(_ amount: Float, of _: ResolvedSpell, on _: ActorValueHolder) {
        charge -= amount
    }
}

@MainActor
struct CasterRuntimeStaffTests {
    /// The fixture's healing spell recast as a staff enchantment with the same effects.
    private static func staffSpell(from spell: ResolvedSpell) throws -> ResolvedSpell {
        let record = try MagicEffectFixture.record(
            type: "ENCH",
            fields: ESMFixture.field("ENIT", EnchantmentFixture.enit(
                cost: 40, flags: 1, castingType: 1, delivery: 0, chargeTime: 0.5
            ))
        )
        return try ResolvedSpell(
            id: spell.id, record: .staff(Enchantment(record: record, localized: false)),
            sourcePlugin: spell.sourcePlugin, effects: spell.effects, cost: spell.cost
        )
    }

    @Test func aStaffCastSpendsChargeNotMagicka() throws {
        let store = WorldStateStore()
        let (spellbook, _) = try SpellbookFixture.runtime(store: store)
        let values = SpellbookFixture.values(store: store)
        let runtime = CasterRuntime(spellbook: spellbook, values: values, world: FakeCasterWorld())
        let healing = try #require(spellbook.record(
            SpellbookFixture.key(SpellbookFixture.Spell.fastHealing)
        ))
        let staffs = FakeStaffs()
        staffs.spell = try Self.staffSpell(from: healing)
        staffs.charge = 1000
        runtime.staffs = staffs

        #expect(runtime.begin(.right, on: .player).failure == nil)
        runtime.advance(delta: 0.5, on: .player)
        #expect(runtime.release(.right, on: .player).isCast)

        #expect(values.current(of: .player).magicka == 100)
        #expect(staffs.charge < 1000)

        staffs.charge = 0
        let refused = runtime.begin(.right, on: .player).failure
        guard case .staffOutOfCharge? = refused else {
            Issue.record("expected an empty staff to refuse, got \(String(describing: refused))")
            return
        }
    }
}
