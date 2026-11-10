// One placed model the cell builder resolved, before it becomes a render placement.

public import OpenSkyBehavior
public import OpenSkyFormatsCore
public import OpenSkyObjectAnimation
public import OpenSkyRenderCore
public import OpenSkyRendering
import OpenSkyRenderResources
public import simd

/// One resolved placement, sortable into instancing-ready order.
nonisolated public struct ResolvedInstance {
    /// Normalized mesh path — primary grouping key.
    public let sortKey: String
    /// REFR FormID — deterministic tie-break within one model.
    public let formID: UInt32
    /// Raw MODL path, for the bounds lookup in MeshLibrary.
    let modelPath: String
    let model: RenderModel
    /// The base's MODS texture sets; empty for a model drawn as authored.
    let surface: ModelSurfaceOverride
    let transform: float4x4
    /// The behaviour set when `model` is this reference's own node-skinned copy.
    var animated: BehaviorProjectAsset?
    /// The reference's `XEMI`, for external-emittance shapes.
    var emittance: EmittanceSource?
    /// A door whose `Open` and `Close` sequences move its leaves.
    public var isSequenceDoor = false
    /// What drives the sequence door's open state.
    public var sequenceDoorKind = CellSequenceDoor.Kind.door
    /// A TREE's wind motion; nil for every other base.
    public var treeMotion: TreeMotion?
}
