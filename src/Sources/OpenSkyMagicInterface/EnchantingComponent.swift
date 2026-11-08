// The player's enchanting state: the base enchantments disenchanting taught, and every
// enchantment made at an arcane enchanter, which no plugin holds. An item copy names a
// made enchantment by its id. See docs/engine/enchanting.md.

import Foundation
public import OpenSkyFormatsESM
public import OpenSkyWorldState

/// One enchantment the player made: each base record scaled by its power.
nonisolated public struct MadeEnchantment: Equatable, Sendable {
    /// The base ENCH records, in the order they were chosen.
    public let bases: [ReferenceKey]
    /// Per base, a factor on every magnitude or duration its effects let power change.
    public let powers: [Float]
    /// A weapon's full charge; zero on apparel.
    public let capacity: Float
    /// What one hit spends at Enchanting 0; zero on apparel. The skill term applies
    /// at each use, because UESP says the charge is "calculated at the moment of the usage".
    public let unskilledCostPerUse: Float
    /// What the readouts call it, from the first base.
    public let name: String

    /// A base without a power gets zero, so a short list cannot misalign.
    public init(
        bases: [ReferenceKey],
        powers: [Float],
        capacity: Float,
        unskilledCostPerUse: Float,
        name: String
    ) {
        self.bases = bases
        self.powers = bases.indices.map { index in
            let power = index < powers.count ? powers[index] : 0
            return power.isFinite ? max(0, power) : 0
        }
        self.capacity = capacity.isFinite ? max(0, capacity) : 0
        self.unskilledCostPerUse = unskilledCostPerUse.isFinite ? max(0, unskilledCostPerUse) : 0
        self.name = name
    }

    /// The skill must stay below 200, where a use would cost nothing.
    public static let skillCap: Float = 199

    /// `1 - sqrt(skill / 200)`, the skill term of a weapon enchantment's cost per use.
    public static func skillCostFactor(_ skill: Float) -> Float {
        let clamped = skill.isFinite ? min(max(0, skill), skillCap) : 0
        return 1 - (clamped / 200).squareRoot()
    }

    /// What one hit spends for a wielder whose Enchanting is `skill` now.
    public func costPerUse(atSkill skill: Float) -> Float {
        unskilledCostPerUse * Self.skillCostFactor(skill)
    }
}

nonisolated public struct EnchantingState: WorldStateComponent, Sendable {
    /// Made enchantments take mod index 0xFF, which no plugin can use, below the
    /// brewed potions' half of it.
    public static let firstMadeID: UInt32 = 0xFF60_0000

    /// Base enchantments the player can apply, ascending so equal state encodes equally.
    public private(set) var known: [ReferenceKey]
    /// Made enchantments by id. Ids count up from `firstMadeID` and are never reused.
    public private(set) var made: [FormID: MadeEnchantment]

    public static var componentKind: WorldStateComponentKind {
        .enchanting
    }

    public init(known: [ReferenceKey] = [], made: [FormID: MadeEnchantment] = [:]) {
        self.known = Array(Set(known)).sorted()
        self.made = made
    }

    public var isEmpty: Bool {
        known.isEmpty && made.isEmpty
    }

    public func knows(_ base: ReferenceKey) -> Bool {
        known.contains(base)
    }

    public static func isMade(_ id: FormID) -> Bool {
        id.rawValue >= firstMadeID && id.rawValue < CreatedRange.end
    }

    public func learning(_ base: ReferenceKey) -> EnchantingState {
        EnchantingState(known: known + [base], made: made)
    }

    /// This state with `enchantment` stored under a new id, and that id.
    public func making(_ enchantment: MadeEnchantment) -> (state: EnchantingState, id: FormID) {
        let next = made.keys.map(\.rawValue).max().map { $0 + 1 } ?? Self.firstMadeID
        var updated = made
        updated[FormID(next)] = enchantment
        return (EnchantingState(known: known, made: updated), FormID(next))
    }

    /// Where made ids stop: the brewed potions start there.
    private enum CreatedRange {
        static let end: UInt32 = 0xFF80_0000
    }
}

nonisolated extension WorldStateComponentKind {
    public static let enchanting = Self(
        rawValue: "enchanting", order: 42, affectsCellBuild: false
    )
}
