import OpenSkyCells
public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkySessionInterface

/// What `MapRecordsAdapter` reads from the session.
@MainActor
public protocol MapRecordsHost: AnyObject {
    var streamer: any CellStreamerPort { get }
    var menuRecords: (any MenuRecordsPort)? { get }
}

/// Part of `MapWorldAdapter` that reads the map's records.
public struct MapRecordsAdapter {
    public let game: any MapRecordsHost
}

extension MapRecordsAdapter {
    public var records: MenuRecordData? {
        game.menuRecords?.menuRecords
    }

    /// The map of the worldspace the player stands in, or of its map parent.
    public var mapWorldspace: Worldspace? {
        guard let records else { return nil }
        return records.mapWorldspace(of: game.streamer.worldspaceEditorID)
    }

    public var mapSettings: MenuMapSettings {
        records?.mapSettings ?? .vanilla
    }
}
