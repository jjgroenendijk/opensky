public import OpenSkyFactionsInterface

/// What the world adapters use of `FactionRuntime`.
public protocol FactionRuntimePort {
    var derivation: HostilityDerivation { get }
}
