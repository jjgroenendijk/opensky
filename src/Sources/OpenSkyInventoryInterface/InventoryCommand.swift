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

nonisolated extension InventoryResult: Equatable where Value: Equatable {}
nonisolated extension InventoryResult: Sendable where Value: Sendable {}
