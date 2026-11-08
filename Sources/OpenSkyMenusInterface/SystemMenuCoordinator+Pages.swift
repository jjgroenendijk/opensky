import Foundation
import OpenSkyFormatsCore
import OpenSkyGameData
import OpenSkyRendering

/// The open page and its rows, for the readout and the readout.
nonisolated public struct SystemMenuPageSnapshot: Equatable, Sendable {
    public let rows: [String]
    public let selectedIndex: Int

    public init(
        rows: [String],
        selectedIndex: Int
    ) {
        self.rows = rows
        self.selectedIndex = selectedIndex
    }
}
