// One player setting per load-time optimisation, so one build can measure each one
// on and off (docs/tools/benchmark.md#load-optimisation-switches).

public import OpenSkyFormatsCore

nonisolated public enum LoadingOptimisationSetting: String, CaseIterable, Sendable {
    case pluginReadAhead
    case archiveReadAhead
    case parallelRecords
    case parallelFormIDIndex
    case prebuildIndexes
    case recordIndexCache

    public var id: PlayerSettingID {
        PlayerSettingID("loading.\(rawValue)")
    }

    public var option: LoadOptimisations {
        switch self {
        case .pluginReadAhead: .pluginReadAhead
        case .archiveReadAhead: .archiveReadAhead
        case .parallelRecords: .parallelRecords
        case .parallelFormIDIndex: .parallelFormIDIndex
        case .prebuildIndexes: .prebuildIndexes
        case .recordIndexCache: .recordIndexCache
        }
    }

    /// `PluginReadAhead` for `.pluginReadAhead`, for control identifiers.
    public var controlName: String {
        rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }

    public var title: String {
        switch self {
        case .pluginReadAhead: "Read plugins ahead"
        case .archiveReadAhead: "Read archive files ahead"
        case .parallelRecords: "Decode records on every core"
        case .parallelFormIDIndex: "Index plugins on every core"
        case .prebuildIndexes: "Build record indexes during the world load"
        case .recordIndexCache: "Keep plugin record indexes in the asset cache"
        }
    }

    public var toolTip: String {
        switch self {
        case .pluginReadAhead: "Ask the disk for a whole plugin file as soon as it opens"
        case .archiveReadAhead: "Ask the disk for a whole archived file before reading it"
        case .parallelRecords: "Decode the records of one type on all CPU cores"
        case .parallelFormIDIndex: "Build each plugin's record index on its own CPU core"
        case .prebuildIndexes: "Build the cell builder's indexes before the first cell loads"
        case .recordIndexCache:
            "Save each plugin's record index and read it back while the plugin is unchanged"
        }
    }

    static var definitions: [PlayerSettingDefinition] {
        allCases.map {
            PlayerSettingDefinition(
                id: $0.id, group: .opensky, kind: .toggle, title: $0.title,
                defaultValue: 1, isApplied: true
            )
        }
    }
}

extension LoadOptimisations {
    /// The switches the `loading.*` settings turn on.
    public init(settings: PlayerSettingsStore) {
        self = LoadingOptimisationSetting.allCases.reduce(into: []) { options, setting in
            if settings.bool(setting.id) {
                options.insert(setting.option)
            }
        }
    }
}
