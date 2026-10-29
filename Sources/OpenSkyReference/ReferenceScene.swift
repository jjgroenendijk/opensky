// A scene playing in the Windows game, as the bridge plugin reports it.

import Foundation

nonisolated public struct ReferenceScene: Codable, Equatable, Sendable {
    nonisolated public struct Actor: Codable, Equatable, Sendable {
        public var alias: UInt32
        /// 0 while the alias is empty.
        public var referenceFormID: UInt32
        /// True while the actor's 3D is loaded.
        public var loaded: Bool
        public var disabled: Bool?
        public var dead: Bool?
    }

    public var formID: UInt32
    /// The phase index from 0; -1 while the scene plays but has not entered a phase.
    public var phase: Int32
    public var actors: [Actor]
}
