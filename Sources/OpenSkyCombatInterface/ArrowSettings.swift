// What happens to an arrow after it lands, and the notice an empty quiver shows.
// See docs/engine/projectiles.md, "After the impact".

import Foundation
import OpenSkyGameData

nonisolated public struct ArrowSettings: Equatable, Sendable {
    /// `fCombatMissileStickDepth`: how far past the contact point a stuck arrow sits.
    public var stickDepth: Float = 20
    /// `fAttachedArrowAgeMax`: seconds an arrow stays stuck in an actor.
    public var attachedAgeMax: Float = 10
    /// `iArrowInventoryChance`: percent chance an arrow that hits an actor joins its inventory.
    public var inventoryChance = 33
    /// `sNoArrows` and `sNoBolts`, or the editor IDs without a string table.
    public var noArrowsText = "sNoArrows"
    public var noBoltsText = "sNoBolts"

    public static let vanilla = Self()

    public init() {}

    /// `text` resolves a string setting through the plugin's string table.
    public static func resolve(
        store: GameSettingStore, text: GameTextResolver = { _ in nil }
    ) -> Self {
        var settings = vanilla
        store.read("fCombatMissileStickDepth", into: &settings, \.stickDepth)
        store.read("fAttachedArrowAgeMax", into: &settings, \.attachedAgeMax)
        store.read("iArrowInventoryChance", into: &settings, \.inventoryChance)
        if let value = store.text("sNoArrows").flatMap({ text($0) }) {
            settings.noArrowsText = value
        }
        if let value = store.text("sNoBolts").flatMap({ text($0) }) {
            settings.noBoltsText = value
        }
        return settings
    }
}
