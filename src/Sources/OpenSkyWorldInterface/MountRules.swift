import Foundation
import simd

nonisolated public enum MountRefusal: String, Equatable, Sendable {
    case alreadyRiding = "the player already rides"
    case dead = "it is dead"
    case noSaddle = "its skeleton has no saddle bone"
    case needsPerk = "Allow Mount Actor does not pass for it"
    case ridden = "somebody rides it"
    case notLoaded = "it is not loaded"
}

/// What kind of actor a mount is. It picks the graph events of the mount and dismount.
nonisolated public enum MountKind: String, Equatable, Sendable {
    case horse
    case dragon
}
