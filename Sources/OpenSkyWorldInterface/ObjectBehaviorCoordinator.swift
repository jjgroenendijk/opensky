import Foundation
import OpenSkyBehavior
import OpenSkyFormatsAnimation
import OpenSkyFormatsMesh
import OpenSkyGameData

/// One line of the object animation readout.
nonisolated public struct ObjectAnimationRow: Equatable, Sendable {
    public let reference: UInt32
    public let project: String
    public let events: [String]
    public let activeState: String?
    /// Every active state, outermost first; a blend runs several machines at once.
    public var activeStates: [String] = []
    /// True while a clip the graph reached is still loading, so the pose holds.
    public var isWaitingForClip = false

    public init(reference: UInt32, project: String, events: [String], activeState: String?) {
        self.reference = reference
        self.project = project
        self.events = events
        self.activeState = activeState
    }
}
