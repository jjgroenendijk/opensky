import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldState

/// What opening one book did.
nonisolated public struct SpellTomeReading: Equatable, Sendable {
    /// True when this reading added the spell to the reader's spellbook.
    public let taught: Bool
    /// True when the reader had already opened this book, which is the state
    /// the "Read" mark exists to answer.
    public let alreadyRead: Bool

    public init(
        taught: Bool,
        alreadyRead: Bool
    ) {
        self.taught = taught
        self.alreadyRead = alreadyRead
    }
}
