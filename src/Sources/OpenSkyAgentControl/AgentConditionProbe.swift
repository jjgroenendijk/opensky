// The arguments of `state condition`: one function, the reference it runs on, its two
// parameters as typed, and the other reference a function with no reference parameter reads.

import Foundation

nonisolated public struct AgentConditionProbe: Equatable, Sendable {
    public var function: String
    public var reference: String
    public var parameter: String?
    public var parameter2: String?
    public var target: String?

    public init(
        function: String, reference: String = "player", parameter: String? = nil,
        parameter2: String? = nil, target: String? = nil
    ) {
        self.function = function
        self.reference = reference
        self.parameter = parameter
        self.parameter2 = parameter2
        self.target = target
    }
}
