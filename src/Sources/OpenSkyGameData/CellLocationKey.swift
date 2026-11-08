// What decides the location a built cell belongs to (docs/formats/locations.md#cell-link).

public import OpenSkyFormatsESM

nonisolated public struct CellLocationKey: Hashable, Sendable {
    public let location: CellSceneLocation?
    /// The cell's `XLCN` link, in its owner plugin's FormID space.
    public let locationLink: FormID?
    public let ownerPluginName: String?
    public let worldspace: FormID?

    public init(
        location: CellSceneLocation?,
        locationLink: FormID?,
        ownerPluginName: String?,
        worldspace: FormID?
    ) {
        self.location = location
        self.locationLink = locationLink
        self.ownerPluginName = ownerPluginName
        self.worldspace = worldspace
    }
}
