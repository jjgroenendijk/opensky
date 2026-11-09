// The record stores the AI adapters read. A port, so a test host can pass them without
// the whole world data.

public import OpenSkyAIPackages
public import OpenSkyCells
public import OpenSkyFormatsESM
public import OpenSkyGameData

/// The loaded records and tuning an AI adapter reads.
nonisolated public protocol AIRecordsPort: WorldRecordsPort {
    var movementTypes: MovementTypeStore { get }
    var packageStore: PackageStore? { get }
    var scriptFileSystem: (any GameFileSource)? { get }
    var shoutStore: ShoutStore? { get }
}

extension WorldDataStores: AIRecordsPort {}
