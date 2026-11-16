// What `state music` shows of the music director: the playing music type and track, so a
// check can compare them with the music type the reference game reports.

public import OpenSkyFormatsESM

/// The music the director plays now, and why it plays it.
public struct MusicReadout: Equatable, Sendable {
    public var musicType = ""
    public var musicTypeFormID: FormID?
    public var state = ""
    public var trackPath: String?
    public var trackIndex = 0
    public var trackCount = 0
    public var elapsedSeconds: Float = 0
    public var paused = false
    public var combat = false
    /// The selection a special moment, such as a level up, interrupted; nil outside one.
    public var interruptedBySpecial: String?
    public var scriptedMusic: [FormID] = []
    public var enabled = true
    public var refusal: String?

    public init() {}
}
