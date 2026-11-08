/// One native call a script waits in, such as `Utility.Wait` or an animation event.
nonisolated public struct PapyrusWaitReadout: Equatable, Sendable {
    public let script: String
    /// `Script.Function` of the native the script waits in.
    public let native: String
    public let request: String

    public init(script: String, native: String, request: String) {
        self.script = script
        self.native = native
        self.request = request
    }
}
