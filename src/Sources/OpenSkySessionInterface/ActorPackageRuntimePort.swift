public import OpenSkyFormatsESM
public import OpenSkyWorldInterface

/// What the world adapters use of `ActorPackageRuntime`.
public protocol ActorPackageRuntimePort {
    func conditionResolution(isWithin: (Package.Location, ReferenceKey) -> Bool)
        -> PackageConditionResolution
    func currentPackage(for actor: ReferenceKey) -> ResolvedPackage?

    func source(for actor: ReferenceKey) -> PackageSource?
}
