import Foundation

nonisolated public struct ContainerMenuControlSnapshot: Equatable, Sendable {
    /// One line per row of the active side, already formatted.
    public let entryLines: [String]
    public let selectedIndex: Int

    public init(
        entryLines: [String],
        selectedIndex: Int
    ) {
        self.entryLines = entryLines
        self.selectedIndex = selectedIndex
    }
}
