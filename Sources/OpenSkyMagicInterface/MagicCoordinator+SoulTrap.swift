import Foundation
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyGameData

/// What one soul trap did.
nonisolated public enum SoulTrapOutcome: Equatable, Sendable {
    case trapped(TrappedSoul, gem: FormID)
    /// No empty gem the player carries holds the soul.
    case noGem(TrappedSoul)
    /// The trap was not the player's, or the session cannot fill a gem.
    case notFilled
}
