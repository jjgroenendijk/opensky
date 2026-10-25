// One landed hit with a weapon that may carry a poison. The poison and its doses are
// world state on the attacker; the magic feature spends a dose and applies the effects.
// See docs/engine/alchemy.md.

import OpenSkyFormatsESM

nonisolated public struct WeaponPoisonHit: Equatable, Sendable {
    public let attacker: ReferenceKey
    /// The weapon or bow that struck. A hit without one carries no poison.
    public let weapon: FormID?
    public let target: ReferenceKey

    public init(attacker: ReferenceKey, weapon: FormID?, target: ReferenceKey) {
        self.attacker = attacker
        self.weapon = weapon
        self.target = target
    }
}

extension WeaponEnchantmentApplying {
    /// A world without an effect runtime delivers no poison.
    public func applyWeaponPoison(_: WeaponPoisonHit) {}
}
