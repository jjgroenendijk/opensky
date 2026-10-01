import Foundation
import OpenSkyFormatsESM

/// One stack as the panel spells it: what it is, how many, and what to call it.
nonisolated public struct ItemStackReadout: Equatable, Sendable {
    public let item: FormID
    public let count: Int32
    /// FULL name when the item index resolves one, else the editor ID, else the
    /// FormID. Never empty, so a readout line always names something.
    public let name: String
    /// Whether these copies were stolen. A stack is keyed by (form, stolen), so the
    /// marker tells apart honest and stolen rows of one form.
    public let stolen: Bool

    public init(item: FormID, count: Int32, name: String, stolen: Bool = false) {
        self.item = item
        self.count = count
        self.name = name
        self.stolen = stolen
    }
}
