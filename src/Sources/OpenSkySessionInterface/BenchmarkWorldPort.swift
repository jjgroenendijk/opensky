public import OpenSkyAgentControl

/// What the world adapters use of `BenchmarkWorldAdapter`.
public protocol BenchmarkWorldPort: AnyObject {
    var isRunning: Bool { get }
    var runCount: Int { get }
    func start(_ agent: AgentBenchmarkRequest) throws(AgentFailure)
    func stop()
    var lastRunJSON: AgentJSON? { get }
}
