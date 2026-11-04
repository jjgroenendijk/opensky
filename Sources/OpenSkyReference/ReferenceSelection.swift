// The console's selected reference in the Windows game, as the bridge plugin reports it.

import Foundation

nonisolated public struct ReferenceSelection: Codable, Equatable, Sendable {
    public var formID: UInt32
    /// True once the reference has its model in the scene.
    public var loaded: Bool
    public var disabled: Bool
    /// The actor's running package, 0 for none.
    public var package: UInt32?
    /// The AI process level, high 0 to low 3; -1 for no actor or no process.
    public var processLevel: Int32?
}

/// The answer of the last `condition <name>` line about the picked reference.
nonisolated public struct ReferenceConditionAnswer: Codable, Equatable, Sendable {
    public var name: String
    /// False when the game has no such function or no reference is picked.
    public var answered: Bool
    public var value: Float?
}
