import Foundation
import OpenSkyFormatsESM

/// One stack as the panel spells it: what it is, how many, and what to call it.
nonisolated public struct ItemStackReadout: Equatable, Sendable {
    public let item: FormID
    public let count: Int32
    /// FULL name when the item index resolves one, else the editor ID, else the
    /// FormID. Never empty, so a readout line always names something.
    public let name: String
    /// Whether these copies were taken from somebody who owned them (issue
    /// #504). One row per stack, and a stack is keyed by (form, stolen), so an
    /// owner holding honest and stolen copies of one form shows two rows — the
    /// marker is what tells them apart.
    public let stolen: Bool

    public init(item: FormID, count: Int32, name: String, stolen: Bool = false) {
        self.item = item
        self.count = count
        self.name = name
        self.stolen = stolen
    }
}
