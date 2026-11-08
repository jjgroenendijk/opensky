public import OpenSkyFormatsESM

/// What the world adapters use of `LoadingScreenCoordinator`.
public protocol LoadingScreenPort: AnyObject {
    associatedtype LoadingScreenSession: LoadingScreenSessionPort
    func begin(at time: Double)
    func beginLoad(at time: Double)
    func cancel()
    func destinationKnown(location: ResolvedFormID?, at time: Double)
    @discardableResult func force(editorID: String, at time: Double) -> Bool
    var isCovering: Bool { get }
    var isWaitingForDestination: Bool { get }
    func loadFinished(at time: Double)
    func releaseForced(at time: Double)
    var session: LoadingScreenSession? { get }
    var shownCount: Int { get }
    func tick(time: Double)
    func turn(byDegrees degrees: Float, at time: Double)
    func destinationReady(location: ResolvedFormID?, at time: Double)
}
