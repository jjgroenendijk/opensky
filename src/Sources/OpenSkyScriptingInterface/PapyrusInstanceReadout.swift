/// One script attached to a reference, with its live variables as `name = value` text.
nonisolated public struct PapyrusInstanceReadout: Equatable, Sendable {
    public let script: String
    public let state: String
    /// An object variable shows the reference it holds, such as `object(0x00012345)`.
    public let variables: [String]

    public init(script: String, state: String, variables: [String]) {
        self.script = script
        self.state = state
        self.variables = variables
    }
}
