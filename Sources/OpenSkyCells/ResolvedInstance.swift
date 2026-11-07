// One placed model the cell builder resolved, before it becomes a render placement.

import OpenSkyBehavior
import OpenSkyFormatsCore
import OpenSkyObjectAnimation
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRenderResources
import simd

/// One resolved placement, sortable into instancing-ready order.
nonisolated public struct ResolvedInstance {
    /// Normalized mesh path — primary grouping key.
    public let sortKey: String
    /// REFR FormID — deterministic tie-break within one model.
    public let formID: UInt32
    /// Raw MODL path, for the bounds lookup in MeshLibrary.
    public let modelPath: String
    public let model: RenderModel
    /// The base's MODS texture sets; empty for a model drawn as authored.
    public let surface: ModelSurfaceOverride
    public let transform: float4x4
    /// The behaviour set when `model` is this reference's own node-skinned copy.
    public var animated: BehaviorProjectAsset?
    /// The reference's `XEMI`, for external-emittance shapes.
    public var emittance: EmittanceSource?
    /// A door whose `Open` and `Close` sequences move its leaves.
    public var isSequenceDoor = false
    /// What drives the sequence door's open state.
    public var sequenceDoorKind = CellSequenceDoor.Kind.door
    /// A TREE's wind motion; nil for every other base.
    public var treeMotion: TreeMotion?
}
