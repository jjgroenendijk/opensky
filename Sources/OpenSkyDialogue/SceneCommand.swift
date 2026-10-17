// What the scene coordinator asks the app to do. See docs/engine/coordinators.md.

/// One change to the world outside scene playback.
nonisolated public enum SceneCommand: Equatable, Sendable {
    /// A scene actor said a line: the app voices it and may show its subtitle.
    case speak(SceneLine)
}
