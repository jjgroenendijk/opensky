// A vendor faction's trading rules, from the CK wiki Faction page, Vendor tab
// (<https://ck.uesp.net/wiki/Faction>), and "Creating a Merchant": "If you don't add
// a start and end time, the merchant wont offer services." See
// docs/engine/vendor-factions.md.

import Foundation
public import OpenSkyFormatsESM
import simd

/// When a vendor trades, from the `VENV` start and end hours.
nonisolated public struct VendorHours: Equatable, Sendable {
    public let start: UInt16
    public let end: UInt16

    /// Whether `hour` (0 up to 24) falls strictly between the start and the end. The
    /// window never wraps past midnight, so a start at or after the end never trades.
    public func isOpen(atHour hour: Float) -> Bool {
        Float(start) < hour && hour < Float(end)
    }

    public init(start: UInt16, end: UInt16) {
        self.start = start
        self.end = end
    }
}

/// Where a vendor has to stand to trade: the `PLVD` type and its link, with the
/// `VENV` radius. Type numbers are UESP's FACT page.
nonisolated public enum VendorPlace: Equatable, Sendable {
    /// 0: near a placed reference.
    case nearReference(ReferenceKey?)
    /// 1: inside one cell.
    case inCell(ReferenceKey?)
    /// 2: near where the vendor's current package starts.
    case nearPackageStart
    /// 3: near the vendor's own editor location.
    case nearEditorLocation
    /// 6: near the reference the vendor links to with this keyword.
    case linkedReference(keyword: ReferenceKey?)
    /// 12: anywhere.
    case nearSelf
    /// Any other type, such as an alias. It never passes.
    case unread(type: Int32)

    public init(type: Int32, link: ReferenceKey?) {
        self = switch type {
        case 0: .nearReference(link)
        case 1: .inCell(link)
        case 2: .nearPackageStart
        case 3: .nearEditorLocation
        case 6: .linkedReference(keyword: link)
        case 12: .nearSelf
        default: .unread(type: type)
        }
    }
}

nonisolated public struct VendorLocationRule: Equatable, Sendable {
    public let place: VendorPlace
    /// The `VENV` radius in world units. Types 0 and 6 have no minimum; types 2 and
    /// 3 use at least `minimumNearRadius`; type 1 does not read it.
    public let radius: Float

    public static let minimumNearRadius: Float = 100

    public init(place: VendorPlace, radius: Float) {
        self.place = place
        self.radius = radius
    }

    /// Whether the merchant stands where the rule allows. `facts` nil means the
    /// world could not say, which allows the trade rather than guess.
    public func allows(_ facts: VendorPlaceFacts?) -> Bool {
        guard let facts else { return true }
        switch place {
        case .nearSelf:
            return true
        case .unread:
            return false
        case let .inCell(cell):
            return cell != nil && facts.cell == cell
        case .nearReference, .linkedReference:
            guard let target = facts.target else { return false }
            return simd_distance(target, facts.position) <= radius
        case .nearPackageStart, .nearEditorLocation:
            // OpenSky cannot place a package start, so an unplaced point passes.
            guard let target = facts.target else { return true }
            return simd_distance(target, facts.position) <= max(radius, Self.minimumNearRadius)
        }
    }
}

/// Where a merchant stands now, and the point its rule names.
nonisolated public struct VendorPlaceFacts: Equatable, Sendable {
    public let position: SIMD3<Float>
    /// The cell the merchant stands in, as a `CELL` record identity. Nil outdoors.
    public let cell: ReferenceKey?
    /// The reference, editor location, or linked reference the rule names. Nil
    /// when the world cannot place it.
    public let target: SIMD3<Float>?

    public init(position: SIMD3<Float>, cell: ReferenceKey?, target: SIMD3<Float>?) {
        self.position = position
        self.cell = cell
        self.target = target
    }
}

/// The player's two vendor actor values: `Bypass Vendor Keyword Check` (94), which the
/// Merchant perk sets, and `Bypass Vendor Stolen Check` (93). Each counts when not zero.
nonisolated public struct VendorBypass: Equatable, Sendable {
    public var keywords: Bool
    public var stolen: Bool

    public init(keywords: Bool = false, stolen: Bool = false) {
        self.keywords = keywords
        self.stolen = stolen
    }
}

/// One actor's vendor role, resolved from its vendor faction.
nonisolated public struct Vendor: Equatable, Sendable {
    public let faction: ReferenceKey
    public let factionName: String
    /// The `VENC` merchant chest, or nil when the faction names none — then
    /// the vendor sells from its own inventory.
    public let merchantChest: ReferenceKey?
    /// Nil when the faction has no `VENV`, which offers no services.
    public let hours: VendorHours?
    /// Every keyword the `VEND` list names, flattened through nested lists.
    /// Nil when the faction authors no list, which gates nothing.
    public let listKeywords: Set<ReferenceKey>?
    /// `VENV`'s "Not Buy/Sell": trade what does *not* match the list.
    public let negatesList: Bool
    /// `VENV`'s "Only Buys Stolen Goods": this vendor is a fence.
    public let buysStolen: Bool
    /// The `PLVD` rule, or nil when the faction has none.
    public var location: VendorLocationRule?
    /// The trailing `CITC`/`CTDA` run, run on the merchant.
    public var conditions = ConditionList()
    /// The plugin the faction came from, which the conditions resolve against.
    public var sourcePlugin = ""

    /// Whether this vendor buys and sells an item carrying `keywords`.
    public func trades(keywords: Set<ReferenceKey>) -> Bool {
        guard let listKeywords else { return true }
        let matches = !listKeywords.isDisjoint(with: keywords)
        return matches != negatesList
    }

    public func isOpen(atHour hour: Float) -> Bool {
        hours?.isOpen(atHour: hour) ?? false
    }

    public init(
        faction: ReferenceKey,
        factionName: String,
        merchantChest: ReferenceKey?,
        hours: VendorHours?,
        listKeywords: Set<ReferenceKey>?,
        negatesList: Bool,
        buysStolen: Bool
    ) {
        self.faction = faction
        self.factionName = factionName
        self.merchantChest = merchantChest
        self.hours = hours
        self.listKeywords = listKeywords
        self.negatesList = negatesList
        self.buysStolen = buysStolen
    }
}
