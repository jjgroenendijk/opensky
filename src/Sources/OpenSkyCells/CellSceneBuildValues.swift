// The values a cell build passes between its parts and returns to callers.

public import OpenSkyFormatsCore
public import OpenSkyFormatsESM

nonisolated public enum CellSceneError: Error, Equatable {
    /// No WRLD record carries the requested editor ID.
    case worldspaceNotFound(editorID: String)
    /// The worldspace holds no CELL at the requested grid slot.
    case cellNotFound(worldspaceEditorID: String, gridX: Int32, gridY: Int32)
    case interiorCellNotFound(formID: FormID)
    case doorReferenceNotFound(formID: FormID)
    case doorHasNoTeleport(formID: FormID)
    case teleportDestinationNotFound(formID: FormID)
    /// A record the build needs exists but its typed decode threw.
    case malformedRecord(type: FourCC, formID: FormID, reason: String)
}

/// Per-build skip accounting; folded into CellLoadSummary at the end.
nonisolated public struct BuildCounts: Sendable {
    public var totalRefs = 0
    public var malformedRefs = 0
    public var unsupportedBases = 0
    public var markers = 0
    var modelFailures = 0
    /// Dropped like an initially-disabled record.
    public var runtimeDisabled = 0
    /// Not the header `deleted` flag, which never reaches a build.
    public var runtimeDeleted = 0
    /// Dropped by the initially-disabled flag or a disabled enable parent.
    public var baselineDisabled = 0
    /// `XESP` links whose parent is outside this build's references.
    public var unresolvedEnableParents = 0
    /// Kept apart from `totalRefs`, the plugin's own count.
    public var spawnedRefs = 0
    /// Spawns past the 24-bit object ID space. Zero in practice.
    public var unaddressableSpawns = 0
}

/// A STAT or ModelBase base resolved to its drawable model path.
nonisolated public struct ResolvedBase: Sendable {
    public let formID: FormID
    public let recordType: FourCC
    /// Nil = marker base (no MODL), nothing to draw.
    public let modelPath: String?
    /// The base is flagged as a marker, so its model is not drawn either.
    public let isEditorMarker: Bool
    /// MODS: the texture sets that replace single shapes of the model.
    public let alternateTextures: [ModelData.AlternateTexture]
    /// STAT `DNAM`: the `MATO` laid over its upward faces.
    public var directionalMaterial: StaticObject.DirectionalMaterial?
    /// TREE `CNAM`: how the tree moves in the wind.
    public var treeData: ModelBaseDetails.TreeData?
}

/// A located CELL and its cell-children group; nil children means no references.
nonisolated public struct FoundCell: Sendable {
    public let cell: Cell
    public let formID: UInt32
    public let children: ESMGroup?
}

/// The world-children group and its WRLD; DNAM feeds the LAND-less terrain fallback.
nonisolated public struct FoundWorld: Sendable {
    /// The first plugin's world children group; nil for a worldspace only a
    /// later plugin defines.
    public let children: ESMGroup?
    public let worldspace: Worldspace?
    /// The WRLD's load-order FormID.
    public let formID: FormID
}
