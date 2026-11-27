// How one dialogue line is voiced: with or without its lip track, and through which
// output model. See docs/engine/dialogue.md (response flags).

public import OpenSkyFormatsESM

nonisolated public struct SpokenLineOptions: Equatable, Sendable {
    public static let standard = Self()

    /// False for an `INFO` with `ENAM` `0x800`: the mouth does not move.
    public var lipSync = true
    /// The `INFO` `ONAM` output model, used when `ENAM` `0x2000` is set.
    public var outputModel: FormID?

    public init(lipSync: Bool = true, outputModel: FormID? = nil) {
        self.lipSync = lipSync
        self.outputModel = outputModel
    }

    /// The options the response flags of `info` ask for.
    public init(_ info: TopicInfo) {
        lipSync = !info.flags.contains(.noLipFile)
        outputModel = info.flags.contains(.hasAudioOutputOverride) ? info.audioOutputOverride : nil
    }
}
