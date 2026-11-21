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

/// The Controls page for the readout: whether it waits for a key, and the key
/// each row is bound to.
nonisolated public struct ControlsPageReadout: Equatable, Sendable {
    nonisolated public struct Row: Equatable, Sendable {
        public let action: String
        /// Nil when no key is bound.
        public let key: String?

        public init(action: String, key: String?) {
            self.action = action
            self.key = key
        }
    }

    public let waitingForKey: Bool
    public let rows: [Row]

    public init(waitingForKey: Bool, rows: [Row]) {
        self.waitingForKey = waitingForKey
        self.rows = rows
    }
}
