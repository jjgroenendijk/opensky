public import OpenSkyFormatsESM
public import OpenSkyMagicInterface

/// What the world adapters use of `HazardRuntime`.
public protocol HazardRuntimePort {
    var active: [ReferenceKey: ActiveHazard] { get }
}
