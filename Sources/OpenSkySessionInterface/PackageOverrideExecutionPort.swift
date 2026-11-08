public import OpenSkyWorldInterface

/// What the world adapters use of `PackageOverrideExecution`.
public protocol PackageOverrideExecutionPort {
    var readout: PackageExecutionReadout { get }
}
