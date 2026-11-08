import Foundation
public import OpenSkyFormatsESM
import OpenSkyGameData

/// A soul a trap caught: its size, and whether only a black gem holds it.
nonisolated public struct TrappedSoul: Equatable, Sendable {
    public let size: SoulLevel
    public let isBlack: Bool

    public init(size: SoulLevel, isBlack: Bool) {
        self.size = size
        self.isBlack = isBlack
    }
}
