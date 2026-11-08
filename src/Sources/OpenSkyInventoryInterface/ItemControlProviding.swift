import Foundation

/// Who an equip or unequip applies to: the player for state and carry weight,
/// or the nearest actor to see the change on a rendered body.
nonisolated public enum EquipmentTargetSelector: Equatable, Sendable {
    case player
    /// The resident ACHR closest to the player.
    case nearestActor
}
