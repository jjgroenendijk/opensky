// What happens to an arrow after it lands, and the notice an empty quiver shows.
// See docs/engine/projectiles.md, "After the impact".

import Foundation
public import OpenSkyFormatsESM
public import OpenSkyGameData

nonisolated public struct ArrowSettings: Equatable, Sendable {
    /// `fCombatMissileStickDepth`: how far past the contact point a stuck arrow sits.
    public var stickDepth: Float = 20
    /// How deep a crossbow bolt sits instead. Read from the game program, no setting.
    public var boltStickDepth: Float = 5
    /// How many arrows one actor shows at once; a new one replaces the oldest.
    public var arrowsPerActor = 3
    /// The materials an arrow sticks in. Nil without material data: every arrow sticks.
    public var holdingMaterials: Set<FormID>?
    /// A bounced arrow leaves at this share of the `PROJ` speed.
    public var bounceSpeedShare: Float = 0.1
    /// `fAttachedArrowAgeMax`: seconds an arrow stays stuck in an actor.
    public var attachedAgeMax: Float = 10
    /// `iArrowInventoryChance`: percent chance an arrow that hits an actor joins its inventory.
    public var inventoryChance = 33
    /// `sNoArrows` and `sNoBolts`, or the editor IDs without a string table.
    public var noArrowsText = "sNoArrows"
    public var noBoltsText = "sNoBolts"

    public static let vanilla = Self()

    public init() {}

    /// Whether an arrow that lands on `material` sticks. Actors always hold arrows.
    public func holds(material: FormID?) -> Bool {
        guard let holdingMaterials, let material else { return true }
        return holdingMaterials.contains(material)
    }

    /// `text` resolves a string setting through the plugin's string table.
    public static func resolve(
        store: GameSettingStore, materials: MaterialTypeIndex? = nil,
        text: GameTextResolver = { _ in nil }
    ) -> Self {
        var settings = vanilla
        settings.holdingMaterials = materials?.arrowHoldingMaterials
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
