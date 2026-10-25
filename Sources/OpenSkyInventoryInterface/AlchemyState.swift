// Alchemy save state: the potions brewed this game, the ingredient effects the player
// knows, and the poison on each weapon. UESP "Skyrim:Alchemy":
// <https://en.uesp.net/wiki/Skyrim:Alchemy>. See docs/engine/alchemy.md.

import OpenSkyFormatsESM
import OpenSkyWorldState

/// One effect of a brewed potion, after the skill and the perks scaled it.
nonisolated public struct CreatedPotionEffect: Equatable, Sendable {
    /// The MGEF in the load-order FormID space, which inventories use.
    public let effect: FormID
    public let magnitude: Float
    public let area: UInt32
    public let duration: UInt32

    public init(effect: FormID, magnitude: Float, area: UInt32, duration: UInt32) {
        self.effect = effect
        self.magnitude = magnitude.isFinite ? max(0, magnitude) : 0
        self.area = area
        self.duration = duration
    }

    public var entry: MagicItemEffect {
        MagicItemEffect(effect: effect, magnitude: magnitude, area: area, duration: duration)
    }
}

/// A potion or poison made at an alchemy lab. No plugin holds it, so the save does.
nonisolated public struct CreatedPotion: Equatable, Sendable {
    /// UESP "Skyrim:Alchemy" gives every made potion and poison the weight 0.5.
    public static let weight: Float = 0.5

    public let id: FormID
    public let name: String
    public let isPoison: Bool
    public let value: Int32
    public let effects: [CreatedPotionEffect]

    public init(
        id: FormID, name: String, isPoison: Bool, value: Int32, effects: [CreatedPotionEffect]
    ) {
        self.id = id
        self.name = name
        self.isPoison = isPoison
        self.value = max(0, value)
        self.effects = effects
    }

    /// The `ALCH` record the item index and the magic runtime read.
    public var ingestible: Ingestible {
        var fields = InventoryItemFields()
        fields.name = .inline(name)
        return Ingestible(
            formID: id,
            fields: fields,
            itemValue: ItemValue(value: value, weight: Self.weight),
            flags: isPoison ? .poison : [],
            effects: effects.map(\.entry)
        )
    }
}

/// Every brewed potion of this game, kept on the player.
nonisolated public struct CreatedPotionState: WorldStateComponent, Sendable {
    /// Brewed potions take mod index 0xFF, which no plugin can use, from its upper half;
    /// spawned references count up from the bottom of the same index.
    public static let firstObjectID: UInt32 = 0xFF80_0000

    public private(set) var potions: [CreatedPotion]

    public static var componentKind: WorldStateComponentKind {
        .createdPotions
    }

    public init(potions: [CreatedPotion] = []) {
        self.potions = potions.sorted { $0.id.rawValue < $1.id.rawValue }
    }

    /// The made potion with these effects, so two equal brews stack.
    public func potion(isPoison: Bool, effects: [CreatedPotionEffect]) -> CreatedPotion? {
        potions.first { $0.isPoison == isPoison && $0.effects == effects }
    }

    /// The state with one more potion, and that potion. An equal brew is reused.
    public func adding(
        name: String, isPoison: Bool, value: Int32, effects: [CreatedPotionEffect]
    ) -> (state: CreatedPotionState, potion: CreatedPotion) {
        if let known = potion(isPoison: isPoison, effects: effects) {
            return (self, known)
        }
        let next = (potions.last?.id.rawValue).map { $0 + 1 } ?? Self.firstObjectID
        let made = CreatedPotion(
            id: FormID(next), name: name, isPoison: isPoison, value: value, effects: effects
        )
        return (CreatedPotionState(potions: potions + [made]), made)
    }
}

/// Which effects of each ingredient the player has learned, by effect index.
nonisolated public struct IngredientKnowledgeState: WorldStateComponent, Sendable {
    /// An `INGR` record lists four effects.
    public static let effectsPerIngredient = 4

    /// Bit `n` set means the effect at index `n` is known.
    public private(set) var known: [FormID: UInt8]

    public static var componentKind: WorldStateComponentKind {
        .ingredientKnowledge
    }

    public init(known: [FormID: UInt8] = [:]) {
        self.known = known.filter { $0.value != 0 }
    }

    public func knows(_ index: Int, of ingredient: FormID) -> Bool {
        guard (0 ..< 8).contains(index) else { return false }
        return (known[ingredient] ?? 0) & (1 << UInt8(index)) != 0
    }

    public func knownIndices(of ingredient: FormID) -> [Int] {
        (0 ..< Self.effectsPerIngredient).filter { knows($0, of: ingredient) }
    }

    public func learning(_ indices: some Sequence<Int>, of ingredient: FormID)
        -> IngredientKnowledgeState
    {
        var mask = known[ingredient] ?? 0
        for index in indices where (0 ..< 8).contains(index) {
            mask |= 1 << UInt8(index)
        }
        var updated = known
        updated[ingredient] = mask
        return IngredientKnowledgeState(known: updated)
    }
}

/// The poison on one weapon and the hits it has left.
nonisolated public struct WeaponPoison: Equatable, Sendable {
    public let poison: FormID
    public let doses: Int32

    public init(poison: FormID, doses: Int32) {
        self.poison = poison
        self.doses = max(0, doses)
    }
}

/// The poisons on an actor's weapons, by weapon FormID.
nonisolated public struct WeaponPoisonState: WorldStateComponent, Sendable {
    public private(set) var poisons: [FormID: WeaponPoison]

    public static var componentKind: WorldStateComponentKind {
        .weaponPoison
    }

    public init(poisons: [FormID: WeaponPoison] = [:]) {
        self.poisons = poisons.filter { $0.value.doses > 0 }
    }

    public var isEmpty: Bool {
        poisons.isEmpty
    }

    /// A new poison replaces the one the weapon carries.
    public func applying(_ poison: WeaponPoison, to weapon: FormID) -> WeaponPoisonState {
        var updated = poisons
        updated[weapon] = poison
        return WeaponPoisonState(poisons: updated)
    }

    /// The state after one hit with `weapon`, and the poison that hit delivers.
    public func spendingDose(of weapon: FormID) -> (state: WeaponPoisonState, poison: FormID?) {
        guard let current = poisons[weapon] else { return (self, nil) }
        var updated = poisons
        updated[weapon] = WeaponPoison(poison: current.poison, doses: current.doses - 1)
        return (WeaponPoisonState(poisons: updated), current.poison)
    }
}

nonisolated extension WorldStateComponentKind {
    public static let createdPotions = Self(
        rawValue: "createdPotions", order: 37, affectsCellBuild: false
    )
    public static let ingredientKnowledge = Self(
        rawValue: "ingredientKnowledge", order: 38, affectsCellBuild: false
    )
    public static let weaponPoison = Self(
        rawValue: "weaponPoison", order: 39, affectsCellBuild: false
    )
}
