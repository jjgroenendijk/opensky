// What the inventory's Charge button offers for one weapon: its charge now, and each
// filled soul gem with what it would add. See docs/engine/inventory-menu.md#recharging.

nonisolated public struct RechargeOffer: Equatable, Sendable {
    nonisolated public struct Gem: Equatable, Sendable {
        public let name: String
        /// The charge this gem adds, in percent of the full charge, before the cap.
        public let addedPercent: Float

        public init(name: String, addedPercent: Float) {
            self.name = name
            self.addedPercent = addedPercent
        }
    }

    public let currentPercent: Float
    public let gems: [Gem]

    public init(currentPercent: Float, gems: [Gem]) {
        self.currentPercent = currentPercent
        self.gems = gems
    }
}
