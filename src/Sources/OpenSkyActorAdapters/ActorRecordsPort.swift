// The record stores the actor adapters read. A port, so a test host can pass them
// without the whole world data.

public import OpenSkyAIPackages
public import OpenSkyCells
public import OpenSkyGameData
public import OpenSkyPlayer
public import OpenSkyWorldInterface

/// The loaded records and tuning an actor adapter reads.
nonisolated public protocol ActorRecordsPort: WorldRecordsPort {
    var dragonFlightSettings: DragonFlightSettings { get }
    var idleStore: IdleStore? { get }
    var mountMovementConfiguration: PlayerMovementConfiguration { get }
    var packageStore: PackageStore? { get }
    var scriptFileSystem: (any GameFileSource)? { get }
}

extension WorldDataStores: ActorRecordsPort {}
