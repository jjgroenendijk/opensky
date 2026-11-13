// The number under the crosshair's prompt for a loose weapon or armour piece, with its
// label from `sHUDDamage` or `sHUDArmorRating`. The movie formats the two values.
// See docs/rendering/hud.md#crosshair-item-stat.

public import OpenSkyGameData
public import OpenSkyInventoryInterface

nonisolated public enum HUDItemStatText: String, GameSettingTextKey {
    case damage = "sHUDDamage"
    case armorRating = "sHUDArmorRating"

    public var fallback: String {
        switch self {
        case .damage: "DAMAGE"
        case .armorRating: "ARMOR RATING"
        }
    }
}

/// One value and its label, the `aFieldValue` and `aFieldText` of `SetCrosshairTarget`.
nonisolated public struct HUDItemStat: Equatable, Sendable {
    public let value: Double
    public let label: String

    /// A weapon's damage or an armour piece's rating; nil for every other item.
    public static func of(
        _ card: InventoryItemCard?, texts: GameSettingTexts<HUDItemStatText>
    ) -> Self? {
        if let damage = card?.damage {
            return Self(value: Double(damage), label: texts[.damage])
        }
        if let rating = card?.armourRating {
            return Self(value: Double(rating), label: texts[.armorRating])
        }
        return nil
    }
}
