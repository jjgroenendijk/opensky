// The sky and the music of the Windows game, as the bridge plugin reports them, to compare
// with OpenSky's `state time` and music state (docs/tools/reference-sky-music.md).

import Foundation

nonisolated public struct ReferenceSky: Codable, Equatable, Sendable {
    /// The game's sky mode: 0 none, 1 interior, 2 sky dome only, 3 full.
    public var mode: Int
    /// How far the weather change has come, 0 to 1.
    public var weatherPercent: Float?
    public var windSpeed: Float?
    public var windAngle: Float?
    public var sun: ReferenceSun?
    public var masser: ReferenceMoon?
    public var secunda: ReferenceMoon?
    public var clouds: [ReferenceCloudLayer]
}

/// The colour, alpha, and texture one sky shape draws with.
nonisolated public struct ReferenceSkyLook: Codable, Equatable, Sendable {
    public var colour: [Float?]
    public var texture: String
    public var blend: Float?
}

nonisolated public struct ReferenceSun: Codable, Equatable, Sendable {
    /// Unit vector from the sky's centre to the sun disc, game axes (+Y north, +Z up).
    public var direction: [Float?]?
    /// The direction the sunlight travels.
    public var lightDirection: [Float?]?
    public var hidden: Bool
    public var glareScale: Float?
    public var look: ReferenceSkyLook?
}

nonisolated public struct ReferenceMoon: Codable, Equatable, Sendable {
    public var direction: [Float?]?
    /// The whole moon is switched off.
    public var hidden: Bool
    public var meshHidden: Bool
    public var shadowHidden: Bool
    /// The texture names the phase; the alpha is the fade.
    public var look: ReferenceSkyLook?
}

nonisolated public struct ReferenceCloudLayer: Codable, Equatable, Sendable {
    public var layer: Int
    public var hidden: Bool
    public var alpha: Float?
    /// Two unnamed layer words, watched over time to find the scroll.
    public var layerWords: [Float?]?
    public var materialOffset: [Float?]?
    public var materialScale: [Float?]?
    public var look: ReferenceSkyLook?
}

nonisolated public struct ReferenceMusic: Codable, Equatable, Sendable {
    public var current: ReferenceMusicType?
    /// The types waiting under the playing one.
    public var queue: [ReferenceMusicType]
}

nonisolated public struct ReferenceMusicType: Codable, Equatable, Sendable {
    public var editorID: String
    public var formID: UInt32
    /// 0 inactive, 1 playing, 2 paused, 3 finishing, 4 finished.
    public var status: Int
    public var track: UInt32
    public var priority: Int
}
