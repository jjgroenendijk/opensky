public import OpenSkyMagicInterface

/// What the world adapters use of `HazardCoordinator`.
public protocol HazardPort: AnyObject {
    associatedtype HazardRuntime: HazardRuntimePort
    var runtime: HazardRuntime { get }
    func spawn(_ placement: HazardPlacement)
}
