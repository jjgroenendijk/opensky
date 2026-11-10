// The console's selected reference in the Windows game, as the bridge plugin reports it.

import Foundation

nonisolated struct ReferenceSelection: Codable, Equatable, Sendable {
    var formID: UInt32
    /// True once the reference has its model in the scene.
    var loaded: Bool
    var disabled: Bool
    /// The actor's running package, 0 for none.
    var package: UInt32?
    /// The AI process level, high 0 to low 3; -1 for no actor or no process.
    var processLevel: Int32?
}

/// The answer of the last `condition <name>` line about the picked reference.
nonisolated struct ReferenceConditionAnswer: Codable, Equatable, Sendable {
    var name: String
    /// False when the game has no such function or no reference is picked.
    var answered: Bool
    var value: Float?
}
