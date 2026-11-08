public import OpenSkyFormatsESM
public import OpenSkyWorldInterface

/// What the world adapters use of `VehicleCore`.
public protocol VehicleCorePort {
    var links: [ReferenceKey: VehicleLink] { get }
    var mounts: [ReferenceKey: ReferenceKey] { get }
}
