// What the inventory and lock coordinators ask the app to do. The coordinator
// decides and returns the commands; the app runs them. See docs/engine/coordinators.md.

import OpenSkyInventoryInterface

/// One change to the world outside the inventory domain.
nonisolated public enum InventoryCommand: Equatable, Sendable {
    /// Readied spells leave the hands `holder` now fills, and worn enchantments are re-read.
    case equipmentChanged(InventoryHolder)
    /// The crosshair prompt re-reads its label, such as after a harvest or a lock change.
    case refreshInteractionTarget
    /// A lock notice on the HUD.
    case showNotice(String)
}

/// An action's answer and the commands the app runs after it.
nonisolated public struct InventoryResult<Value> {
    public let value: Value
    public let commands: [InventoryCommand]

    public init(_ value: Value, commands: [InventoryCommand] = []) {
        self.value = value
        self.commands = commands
    }
}

extension InventoryResult: Equatable where Value: Equatable {}
extension InventoryResult: Sendable where Value: Sendable {}
