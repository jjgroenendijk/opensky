// The player's own weapon damage and armour rating, after skill and perks, which the
// item card and the barter bar show. See docs/engine/barter.md#the-item-card.

public import OpenSkyFormatsESM
import OpenSkyInventoryInterface

nonisolated public struct ShownGearStats {
    /// A weapon's shown damage at a temper level; nil keeps the card's base.
    public var damage: (FormID, Int32) -> Int?
    /// An armour piece's shown rating at a temper level; nil keeps the card's base.
    public var armour: (FormID, Int32) -> Float?
    /// What the bar adds to the worn pieces, such as an armour spell.
    public var armourBonus: Float

    public init(
        damage: @escaping (FormID, Int32) -> Int?,
        armour: @escaping (FormID, Int32) -> Float?,
        armourBonus: Float = 0
    ) {
        self.damage = damage
        self.armour = armour
        self.armourBonus = armourBonus
    }

    /// The card's own base values.
    public static var base: ShownGearStats {
        ShownGearStats(damage: { _, _ in nil }, armour: { _, _ in nil })
    }

    func applied(
        to card: InventoryItemCard, item: FormID, temperLevel: Int32
    ) -> InventoryItemCard {
        var card = card
        if card.damage != nil, let shown = damage(item, temperLevel) {
            card.damage = shown
        }
        if card.armourRating != nil, let shown = armour(item, temperLevel) {
            card.armourRating = shown
        }
        return card
    }
}
