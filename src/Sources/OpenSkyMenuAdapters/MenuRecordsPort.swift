// The record stores the menu adapters read. A port, so a test host can pass them
// without the whole world data.

public import OpenSkyCells
public import OpenSkyGameData
public import OpenSkyPlayer

/// The loaded records and tuning a menu adapter reads.
nonisolated public protocol MenuRecordsPort: WorldRecordsPort {
    var menuRecords: MenuRecordData? { get }
    var movementConfiguration: PlayerMovementConfiguration { get }
    var presentationRecords: PresentationRecordStore? { get }
    var scriptFileSystem: (any GameFileSource)? { get }
}

extension WorldDataStores: MenuRecordsPort {}
