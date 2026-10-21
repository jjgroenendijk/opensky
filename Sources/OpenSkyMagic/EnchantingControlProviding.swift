// The sidebar seam for enchanting: disenchant a carried item, and enchant a plain one
// with known bases and a filled soul gem, as if at an arcane enchanter.
// See docs/engine/enchanting.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyInventoryInterface
import OpenSkyMagicInterface

/// One carried item the panel can act on.
nonisolated public struct EnchantingItemReadout: Equatable, Sendable {
    public let id: FormID
    public let name: String

    public init(id: FormID, name: String) {
        self.id = id
        self.name = name
    }
}

/// One filled soul gem copy the player carries.
nonisolated public struct EnchantingGemReadout: Equatable, Sendable {
    public let gem: SoulGemCandidate
    public let name: String

    public init(gem: SoulGemCandidate, name: String) {
        self.gem = gem
        self.name = name
    }
}

nonisolated public struct EnchantingControlSnapshot: Equatable, Sendable {
    public static let unavailable = EnchantingControlSnapshot(
        isAvailable: false, disenchantable: [], enchantable: [], bases: [], gems: [],
        allowedBases: 1, madeCount: 0, lastActionText: EnchantingOutcome.unavailable.text
    )

    public let isAvailable: Bool
    /// Carried enchanted items whose base the player does not know yet.
    public let disenchantable: [EnchantingItemReadout]
    /// Carried weapons and apparel with no enchantment.
    public let enchantable: [EnchantingItemReadout]
    public let bases: [EnchantingBaseReadout]
    public let gems: [EnchantingGemReadout]
    /// Entry point 80: how many bases one item may take.
    public let allowedBases: Int
    public let madeCount: Int
    public let lastActionText: String

    public init(
        isAvailable: Bool, disenchantable: [EnchantingItemReadout],
        enchantable: [EnchantingItemReadout], bases: [EnchantingBaseReadout],
        gems: [EnchantingGemReadout], allowedBases: Int, madeCount: Int, lastActionText: String
    ) {
        self.isAvailable = isAvailable
        self.disenchantable = disenchantable
        self.enchantable = enchantable
        self.bases = bases
        self.gems = gems
        self.allowedBases = allowedBases
        self.madeCount = madeCount
        self.lastActionText = lastActionText
    }

    public var readoutText: String {
        guard isAvailable else { return lastActionText }
        let known = bases.map(\.name)
        return [
            "Known: \(known.isEmpty ? "none" : known.joined(separator: ", "))",
            "Bases per item: \(allowedBases)   Made: \(madeCount)",
            "Last: \(lastActionText)"
        ].joined(separator: "\n")
    }
}

@MainActor
public protocol EnchantingControlProviding: AnyObject {
    var enchantingSnapshot: EnchantingControlSnapshot { get }
    @discardableResult
    func disenchant(_ item: FormID) -> EnchantingOutcome
    @discardableResult
    func enchant(
        _ item: FormID, with bases: [ReferenceKey], gem: SoulGemCandidate, name: String?
    ) -> EnchantingOutcome
    /// What enchanting would make, without making it.
    func enchantingPreview(
        _ item: FormID, with bases: [ReferenceKey], gem: SoulGemCandidate
    ) -> Result<MadeEnchantment, EnchantingRefusal>
}

extension MagicCoordinator: EnchantingControlProviding {
    public var enchantingSnapshot: EnchantingControlSnapshot {
        guard effects != nil, enchantmentStore != nil, let inventory = world.inventory else {
            return .unavailable
        }
        let state = enchantingState
        let carried = Set(inventory.inventory(of: .player).stacks.map(\.item))
            .sorted { $0.rawValue < $1.rawValue }
        let disenchantable = carried.filter { item in
            guard
                let profile = enchantmentProfile(of: item), !profile.isStaff,
                let root = rootBase(of: profile) else { return false }
            return !state.knows(root)
        }
        let enchantable = carried.filter { item in
            enchantmentProfile(of: item) == nil
                && inventory.copies(of: item, in: .player).contains { $0.enchantment == nil }
                && isEnchantable(item)
        }
        return EnchantingControlSnapshot(
            isAvailable: true,
            disenchantable: disenchantable.map(readout),
            enchantable: enchantable.map(readout),
            bases: knownEnchantingBases,
            gems: carriedGems(inventory).filter { $0.soul != .empty }.map {
                EnchantingGemReadout(gem: $0, name: "\(world.itemName($0.item)) (\($0.soul))")
            },
            allowedBases: appliedEnchantmentsAllowed,
            madeCount: state.made.count,
            lastActionText: lastEnchanting.text
        )
    }

    public func enchantingPreview(
        _ item: FormID, with bases: [ReferenceKey], gem: SoulGemCandidate
    ) -> Result<MadeEnchantment, EnchantingRefusal> {
        preview(item, with: bases, gem: gem)
    }

    private func readout(_ item: FormID) -> EnchantingItemReadout {
        EnchantingItemReadout(id: item, name: world.itemName(item))
    }
}

nonisolated extension EnchantingOutcome {
    public var text: String {
        switch self {
        case .idle: "Nothing done yet."
        case let .learned(item, base): "Disenchanted \(item); learned \(base)."
        case let .enchanted(item, name, charge):
            "Enchanted \(item) with \(name)"
                + (charge.isMetered ? ": \(charge.describedLine)." : ".")
        case let .refused(refusal): refusal.text
        case .unavailable: "Enchanting needs an inventory, the ENCH index and the effects."
        }
    }
}

nonisolated extension EnchantingRefusal {
    public var text: String {
        switch self {
        case .notCarried: "The player does not carry it."
        case .notEnchanted: "It carries no enchantment."
        case .cannotDisenchant: "Its enchantment cannot be learned."
        case .alreadyKnown: "That enchantment is known already."
        case .alreadyEnchanted: "It is enchanted already."
        case .notEnchantable: "Only weapons and apparel take an enchantment."
        case .noBase: "Choose an enchantment."
        case .unknownBase: "The player does not know that enchantment."
        case let .baseDoesNotFit(name): "\(name) does not fit this item."
        case let .tooManyBases(allowed): "Only \(allowed) enchantment(s) per item."
        case .mixedPlugins: "OpenSky combines enchantments of one plugin only."
        case .emptyGem: "The soul gem is empty."
        }
    }
}

extension MadeEnchantment {
    /// One preview line: the name, the power of each base, and a weapon's charge.
    public var previewText: String {
        let powers = powers.map { String(format: "x%.2f", $0) }.joined(separator: ", ")
        guard isWeapon else { return "\(name): power \(powers)" }
        let charge = EnchantmentCharge(capacity: capacity, costPerUse: costPerUse)
        return "\(name): power \(powers), \(charge.describedLine)"
    }
}
