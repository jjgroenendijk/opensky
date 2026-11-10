// The sky and the music of the Windows game, as the bridge plugin reports them, to compare
// with OpenSky's `state time` and music state (docs/tools/reference-sky-music.md).

import Foundation

nonisolated struct ReferenceSky: Codable, Equatable, Sendable {
    /// The game's sky mode: 0 none, 1 interior, 2 sky dome only, 3 full.
    var mode: Int
    /// How far the weather change has come, 0 to 1.
    var weatherPercent: Float?
    var windSpeed: Float?
    var windAngle: Float?
    var sun: ReferenceSun?
    var masser: ReferenceMoon?
    var secunda: ReferenceMoon?
    var clouds: [ReferenceCloudLayer]
}

/// The colour, alpha, and texture one sky shape draws with.
nonisolated struct ReferenceSkyLook: Codable, Equatable, Sendable {
    var colour: [Float?]
    var texture: String
    var blend: Float?
}

nonisolated struct ReferenceSun: Codable, Equatable, Sendable {
    /// Unit vector from the sky's centre to the sun disc, game axes (+Y north, +Z up).
    var direction: [Float?]?
    /// The direction the sunlight travels.
    var lightDirection: [Float?]?
    var hidden: Bool
    var glareScale: Float?
    var look: ReferenceSkyLook?
}

nonisolated struct ReferenceMoon: Codable, Equatable, Sendable {
    var direction: [Float?]?
    /// The whole moon is switched off.
    var hidden: Bool
    var meshHidden: Bool
    var shadowHidden: Bool
    /// The texture names the phase; the alpha is the fade.
    var look: ReferenceSkyLook?
}

nonisolated struct ReferenceCloudLayer: Codable, Equatable, Sendable {
    var layer: Int
    var hidden: Bool
    var alpha: Float?
    /// Two unnamed layer words, watched over time to find the scroll.
    var layerWords: [Float?]?
    var materialOffset: [Float?]?
    var materialScale: [Float?]?
    var look: ReferenceSkyLook?
}

nonisolated struct ReferenceMusic: Codable, Equatable, Sendable {
    var current: ReferenceMusicType?
    /// The types waiting under the playing one.
    var queue: [ReferenceMusicType]
}

nonisolated struct ReferenceMusicType: Codable, Equatable, Sendable {
    var editorID: String
    var formID: UInt32
    /// 0 inactive, 1 playing, 2 paused, 3 finishing, 4 finished.
    var status: Int
    var track: UInt32
    var priority: Int
}
