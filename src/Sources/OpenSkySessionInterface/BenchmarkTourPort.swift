public import OpenSkyWorldInterface

/// What the world adapters use of `BenchmarkTourCoordinator`.
public protocol BenchmarkTourPort: AnyObject {
    var isRunning: Bool { get }
    var snapshot: BenchmarkTourSnapshot? { get }
    func start(
        _ request: BenchmarkRequest,
        machine: BenchmarkMachine,
        appStart: BenchmarkAppStart?
    ) throws(BenchmarkRequestError)
    func stop()
    func tick()
}

/// The default arguments a protocol requirement cannot carry.
extension BenchmarkTourPort {
    public func start(
        _ request: BenchmarkRequest,
        machine: BenchmarkMachine
    ) throws(BenchmarkRequestError) {
        try start(request, machine: machine, appStart: nil)
    }
}
