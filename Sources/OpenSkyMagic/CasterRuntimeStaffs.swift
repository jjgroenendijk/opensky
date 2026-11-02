// A staff casts its enchantment like a spell, but pays from the staff's charge, not
// magicka, and trains no skill. UESP "Skyrim:Staves": "using a staff does not use any
// of the caster's own Magicka; instead, it depletes the staff's charge", and a higher
// school skill lowers the charge cost. See docs/engine/spellcasting.md.

import Foundation
import OpenSkyActorsInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface

/// The staffs actors hold and the charge on each.
@MainActor
public protocol StaffCharging: AnyObject {
    /// The enchantment of the staff in `hand`, as a spell, or nil.
    func staffSpell(in hand: SpellHand, of holder: ActorValueHolder) -> ResolvedSpell?
    /// Charge left on the held staff whose enchantment is `spell`.
    func staffCharge(of spell: ResolvedSpell, on holder: ActorValueHolder) -> Float
    func spendStaffCharge(_ amount: Float, of spell: ResolvedSpell, on holder: ActorValueHolder)
}

extension CasterRuntime {
    /// A held staff's spell, else the spellbook's record.
    func castable(_ key: ReferenceKey) -> ResolvedSpell? {
        staffSpells[key] ?? spellbook.record(key)
    }

    /// What a cast of `spell` can spend: the staff's charge or the caster's magicka.
    func pool(for spell: ResolvedSpell, caster: ActorValueHolder) -> Float {
        guard spell.isStaff else { return values.current(of: caster).magicka }
        return staffs?.staffCharge(of: spell, on: caster) ?? 0
    }

    func pay(_ amount: Float, for spell: ResolvedSpell, caster: ActorValueHolder) {
        guard amount.isFinite, amount > 0 else { return }
        guard spell.isStaff else {
            values.damage(.magicka, by: amount, on: caster)
            return
        }
        staffs?.spendStaffCharge(amount, of: spell, on: caster)
    }
}
