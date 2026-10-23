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

/// What one poisoned hit did.
nonisolated public struct WeaponPoisonReport: Equatable, Sendable {
    public let poison: FormID
    public let dosesLeft: Int32
    /// Timed effects the runtime stored on the target.
    public let storedCount: Int

    public init(poison: FormID, dosesLeft: Int32, storedCount: Int) {
        self.poison = poison
        self.dosesLeft = dosesLeft
        self.storedCount = storedCount
    }
}

extension WeaponEnchantmentApplying {
    /// A world without an effect runtime delivers no poison.
    public func applyWeaponPoison(_: WeaponPoisonHit) -> WeaponPoisonReport? {
        nil
    }
}
