public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyWorldState

nonisolated public struct ImageSpaceLinks: Sendable {
    public let records: EffectRecordStore
    /// The plugin the weather store's `IMSP` links are spelled in.
    public let weatherPlugin: String
    /// The interior's `XCIM` link and its plugin; nil outdoors.
    public var interior: InteriorImageSpace?

    public init(records: EffectRecordStore, weatherPlugin: String) {
        self.records = records
        self.weatherPlugin = weatherPlugin
    }

    public func resolve(_ id: FormID, plugin: String) -> ResolvedImageSpace? {
        records.imageSpaces.resolve(id, fromPlugin: plugin).map {
            ResolvedImageSpace(key: ReferenceKey(resolved: $0.id), record: $0.record)
        }
    }
}

nonisolated public struct InteriorImageSpace: Equatable, Sendable {
    public let imageSpace: FormID?
    public let plugin: String

    public init(imageSpace: FormID?, plugin: String) {
        self.imageSpace = imageSpace
        self.plugin = plugin
    }
}
