// A scene playing in the Windows game, as the bridge plugin reports it.

import Foundation

nonisolated struct ReferenceScene: Codable, Equatable, Sendable {
    nonisolated struct Actor: Codable, Equatable, Sendable {
        var alias: UInt32
        /// 0 while the alias is empty.
        var referenceFormID: UInt32
        /// True while the actor's 3D is loaded.
        var loaded: Bool
        var disabled: Bool?
        var dead: Bool?
        /// The AI process level, high 0 to low 3; -1 for no actor or no process.
        var processLevel: Int32?
    }

    var formID: UInt32
    /// The phase index from 0; -1 while the scene plays but has not entered a phase.
    var phase: Int32
    var actors: [Actor]
}
