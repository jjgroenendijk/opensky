import OpenSkyGameData

nonisolated public struct PlayerHUDSettings: Equatable, Sendable {
    public var crosshair: Bool
    public var compass: Bool
    public var floatingMarkers: Bool
    public var opacity: Float
    public var subtitles: SubtitleSettings

    public init(
        crosshair: Bool, compass: Bool, floatingMarkers: Bool, opacity: Float,
        subtitles: SubtitleSettings = SubtitleSettings(dialogue: false, general: false)
    ) {
        self.crosshair = crosshair
        self.compass = compass
        self.floatingMarkers = floatingMarkers
        self.opacity = opacity
        self.subtitles = subtitles
    }
}
