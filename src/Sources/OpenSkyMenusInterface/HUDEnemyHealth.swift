/// The actor whose health bar the HUD shows; `health` is a fraction of full.
nonisolated public struct HUDEnemyHealth: Equatable, Sendable {
    public let name: String
    public let health: Float

    public init(name: String, health: Float) {
        self.name = name
        self.health = health
    }
}
