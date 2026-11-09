// The record stores the session adapters read. A port, so a test host can pass them
// without the whole world data.

public import OpenSkyCells
public import OpenSkyGameData
public import OpenSkyWorld
public import OpenSkyWorldState

/// The loaded records the audio, runtime-state, and save adapters read.
nonisolated public protocol SessionRecordsPort: WorldRecordsPort, AudioRecordsPort {
    var globalStore: GlobalStore? { get }
}

extension WorldDataStores: SessionRecordsPort {}
