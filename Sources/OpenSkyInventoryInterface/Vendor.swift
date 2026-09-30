import Foundation
import OpenSkyFormatsESM

/// When a vendor trades, from the `VENV` start and end hours.
nonisolated public struct VendorHours: Equatable, Sendable {
    public let start: UInt16
    public let end: UInt16

    /// Whether `hour` (0 up to 24) falls inside the window.
    ///
    /// Start inclusive, end exclusive. An end of 24 or more runs to midnight; a
    /// start after the end wraps past midnight; a start equal to the end is
    /// read as always open (see the file header).
    public func isOpen(atHour hour: Float) -> Bool {
        guard start != end else { return true }
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

/// One actor's vendor role, resolved from its vendor faction.
nonisolated public struct Vendor: Equatable, Sendable {
    public let faction: ReferenceKey
    public let factionName: String
    /// The `VENC` merchant chest, or nil when the faction names none — then
    /// the vendor sells from its own inventory.
    public let merchantChest: ReferenceKey?
    public let hours: VendorHours?
    /// Every keyword the `VEND` list names, flattened through nested lists.
    /// Nil when the faction authors no list, which gates nothing.
    public let listKeywords: Set<ReferenceKey>?
    /// `VENV`'s "Not Buy/Sell": trade what does *not* match the list.
    public let negatesList: Bool
    /// `VENV`'s "Only Buys Stolen Goods": this vendor is a fence.
    public let buysStolen: Bool

    /// Whether this vendor buys and sells an item carrying `keywords`.
    public func trades(keywords: Set<ReferenceKey>) -> Bool {
        guard let listKeywords else { return true }
        let matches = !listKeywords.isDisjoint(with: keywords)
        return matches != negatesList
    }

    public func isOpen(atHour hour: Float) -> Bool {
        hours?.isOpen(atHour: hour) ?? true
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
