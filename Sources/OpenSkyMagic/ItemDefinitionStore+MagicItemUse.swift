// What consuming an item applies, read from the item index. It lives in the
// magic feature because the result names an `ActiveEffectSourceKind`.

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface

nonisolated extension ItemDefinitionStore {
    /// What consuming `id` applies, or nil when it is not something an actor
    /// can eat or drink (issue #469).
    public func magicItemUse(_ id: FormID) -> MagicItemUse? {
        if let ingestible = ingestibles[id.rawValue] {
            return MagicItemUse(
                item: id,
                kind: .potion,
                effects: ingestible.effects,
                consumeSound: ingestible.consumeSound
            )
        }
        guard let ingredient = ingredients[id.rawValue] else { return nil }
        // Eating a raw ingredient applies only its first effect. UESP's
        // "Skyrim:Alchemy Effects" states it directly: "Ingredients listed in
        // bold have that effect as their first, meaning that eating a sample of
        // that ingredient will provide a small version of that effect."
        // <https://en.uesp.net/wiki/Skyrim:Alchemy_Effects>
        return MagicItemUse(
            item: id,
            kind: .ingredient,
            effects: Array(ingredient.effects.prefix(1)),
            consumeSound: nil
        )
    }
}
