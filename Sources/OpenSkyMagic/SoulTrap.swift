// Which soul a dying actor has, and which carried gem it fills. Pure. UESP
// "Skyrim:Souls": "All NPCs, Dremora, and ghosts have Black souls", and every other
// creature's soul follows its level; "Skyrim:Soul Trap (effect)": "Souls will always
// fill the smallest empty Soul Gem that can accommodate it". See docs/engine/soul-trap.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface

/// The creature levels where each soul size starts.
nonisolated public struct SoulTrapSettings: Equatable, Sendable {
    /// `iLesserSoulActorLevel`.
    public var lesserLevel = 4
    /// `iCommonSoulActorLevel`.
    public var commonLevel = 16
    /// `iGreaterSoulActorLevel`.
    public var greaterLevel = 28
    /// `iGrandSoulActorLevel`.
    public var grandLevel = 38

    public static let vanilla = Self()

    public init() {}

    public static func resolve(store: GameSettingStore) -> Self {
        var settings = vanilla
        store.read("iLesserSoulActorLevel", into: &settings, \.lesserLevel)
        store.read("iCommonSoulActorLevel", into: &settings, \.commonLevel)
        store.read("iGreaterSoulActorLevel", into: &settings, \.greaterLevel)
        store.read("iGrandSoulActorLevel", into: &settings, \.grandLevel)
        return settings
    }
}

/// A soul a trap caught: its size, and whether only a black gem holds it.
nonisolated public struct TrappedSoul: Equatable, Sendable {
    public let size: SoulLevel
    public let isBlack: Bool

    public init(size: SoulLevel, isBlack: Bool) {
        self.size = size
        self.isBlack = isBlack
    }
}

/// One carried gem copy a soul could go into.
nonisolated public struct SoulGemCandidate: Equatable, Sendable {
    public let item: FormID
    public let gem: SoulGem
    public let copy: ItemCopy

    public init(item: FormID, gem: SoulGem, copy: ItemCopy) {
        self.item = item
        self.gem = gem
        self.copy = copy
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.item == rhs.item && lhs.copy == rhs.copy
    }

    /// The record's soul, unless this copy holds one of its own.
    public var soul: SoulLevel {
        copy.soul != 0 ? SoulLevel(rawValue: copy.soul) : gem.containedSoul ?? .empty
    }

    /// A black gem's record leaves SLCP out; it holds a grand soul.
    var capacity: Int {
        gem.canHoldNPCSoul ? 5 : Int(gem.capacity?.rawValue ?? 0)
    }
}

nonisolated public enum SoulTrap {
    /// The soul of an actor at `level`. `isNPC` is the `ActorTypeNPC` keyword.
    public static func soul(level: Int, isNPC: Bool, settings: SoulTrapSettings) -> TrappedSoul {
        guard !isNPC else { return TrappedSoul(size: .grand, isBlack: true) }
        let size: SoulLevel = switch level {
        case settings.grandLevel...: .grand
        case settings.greaterLevel...: .greater
        case settings.commonLevel...: .common
        case settings.lesserLevel...: .lesser
        default: .petty
        }
        return TrappedSoul(size: size, isBlack: false)
    }

    /// The charge a soul gives, from UESP "Skyrim:Souls": 250 petty up to 3000 grand.
    public static func charge(of soul: SoulLevel) -> Float {
        switch soul {
        case .petty: 250
        case .lesser: 500
        case .common: 1000
        case .greater: 2000
        case .grand: 3000
        case .empty, .unknown: 0
        }
    }

    /// The smallest empty gem that holds `soul`. A white gem comes before a black one
    /// of the same size, and ties go by form ID.
    public static func gem(for soul: TrappedSoul, among candidates: [SoulGemCandidate])
        -> SoulGemCandidate?
    {
        candidates
            .filter { $0.soul == .empty && holds($0, soul) }
            .min { lhs, rhs in
                (lhs.capacity, lhs.gem.canHoldNPCSoul ? 1 : 0, lhs.item.rawValue)
                    < (rhs.capacity, rhs.gem.canHoldNPCSoul ? 1 : 0, rhs.item.rawValue)
            }
    }

    private static func holds(_ candidate: SoulGemCandidate, _ soul: TrappedSoul) -> Bool {
        if soul.isBlack {
            return candidate.gem.canHoldNPCSoul
        }
        return candidate.capacity >= Int(soul.size.rawValue)
    }
}
