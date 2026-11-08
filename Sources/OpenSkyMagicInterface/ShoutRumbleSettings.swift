import Foundation
import OpenSkyGameData

nonisolated public struct ShoutRumble: Equatable, Sendable {
    public var bigSeconds: Float
    public var bigStrength: Float
    public var smallSeconds: Float
    public var smallStrength: Float

    public init(bigSeconds: Float, bigStrength: Float, smallSeconds: Float, smallStrength: Float) {
        self.bigSeconds = bigSeconds
        self.bigStrength = bigStrength
        self.smallSeconds = smallSeconds
        self.smallStrength = smallStrength
    }
}
