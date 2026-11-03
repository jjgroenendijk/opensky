// The console's selected reference in the Windows game, as the bridge plugin reports it.

import Foundation

nonisolated public struct ReferenceSelection: Codable, Equatable, Sendable {
    public var formID: UInt32
    /// True once the reference has its model in the scene.
    public var loaded: Bool
    public var disabled: Bool
}
