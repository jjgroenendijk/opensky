// A vendor faction's trading rules, from the CK wiki Faction page, Vendor tab
// (<https://ck.uesp.net/wiki/Faction>), and "Creating a Merchant": "If you don't add
// a start and end time, the merchant wont offer services." See
// docs/engine/vendor-factions.md.

import Foundation
import OpenSkyFormatsESM
import simd

/// When a vendor trades, from the `VENV` start and end hours.
nonisolated public struct VendorHours: Equatable, Sendable {
    public let start: UInt16
    public let end: UInt16

    /// Whether `hour` (0 up to 24) falls inside the window.
    ///
    /// Start inclusive, end exclusive. An end of 24 or more runs to midnight; a
    /// start after the end wraps past midnight; a start equal to the end is no
    /// window at all, so the vendor never trades.
    public func isOpen(atHour hour: Float) -> Bool {
        guard start != end else { return false }
        let open = Float(start)
        let close = Float(min(end, 24))
        if open < close {
            return hour >= open && hour < close
        }
        return hour >= open || hour < close
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
    /// A type OpenSky does not read, such as an alias. It never refuses.
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
    /// The `VENV` radius in world units. Zero sets no distance limit: vanilla
    /// vendors author 0 and still trade, so 0 cannot mean "on the exact spot".
    public let radius: Float

    public init(place: VendorPlace, radius: Float) {
        self.place = place
        self.radius = radius
    }

    /// Whether the merchant stands where the rule allows. `facts` nil means the
    /// world could not say, which allows the trade rather than guess.
    public func allows(_ facts: VendorPlaceFacts?) -> Bool {
        guard let facts else { return true }
        switch place {
        case .nearSelf, .unread:
            return true
        case let .inCell(cell):
            return cell == nil || facts.cell == cell
        case .nearReference, .nearPackageStart, .nearEditorLocation, .linkedReference:
            // A point the world cannot place is allowed, for the reason above.
            guard let target = facts.target, radius > 0 else { return true }
            return simd_distance(target, facts.position) <= radius
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
