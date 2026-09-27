// Spawned references (issue #177, roadmap item 12.1.3): objects the running
// game created, which no plugin places and every cell build still has to draw.
//
// A dropped item is the first of them; a summon and a placed atronach are the
// same shape. The representation is deliberately a `WorldStateComponent` rather
// than a list beside the store, so that the M10 machinery absorbs it unchanged:
// `WorldStateStore.set` journals a spawn exactly as it journals a `Disable()`,
// `snapshot()` orders it by `ReferenceKey`, the save writes it as one more
// additive chunk, and `CellStreamer.noteStateMutation` rebuilds the cell it
// landed in. Nothing in this file knows about inventory; dropping an item is
// `InventoryRuntime.remove` followed by one `set` of this component.
//
// The component carries its own cell rather than relying on
// `ReferenceStateDelta.cell`. The delta's cell records where the *most recent*
// mutation happened and is overwritten by every later write, which is right for
// dirty-count attribution and wrong for "where does this object exist": moving
// a dropped item would otherwise be able to strand it in a cell it is no longer
// in. The two agree in practice, because every writer attributes the mutation
// to the same cell it spawns into.
//
// Documented in docs/engine/runtime-state.md.

import Foundation

/// One object the running game placed in the world.
///
/// Every field is what a cell build needs to synthesize a `PlacedReference`:
/// the base record to resolve a model and collision from, where it stands, and
/// how many of it there are when the base is a carryable item.
nonisolated struct ReferenceSpawnState: WorldStateComponent {
    /// The base record this reference places — a MISC, WEAP, ALCH and so on
    /// for a dropped item.
    let base: FormID
    /// The cell the object exists in. Non-optional: an object with no cell is
    /// not in the world, and a build has no way to draw it.
    let location: CellSceneLocation
    /// Position and rotation, in the same game units and radians REFR DATA
    /// uses.
    let placement: PlacedReference.Placement
    /// Uniform scale, matching XSCL semantics.
    let scale: Float
    /// How many of `base` the pile holds, mirroring REFR XCNT. Always at least
    /// one: a spawned reference that places nothing should not exist.
    let count: Int32

    static var componentKind: WorldStateComponentKind {
        .spawn
    }

    var erased: WorldStateComponentValue {
        .spawn(self)
    }

    /// Normalizes on the way in, because this initializer is also the save
    /// decoder's entry point and a corrupt file must degrade rather than fail
    /// the whole load: a non-positive count becomes one, and a scale that is
    /// not a positive finite number becomes one.
    init(
        base: FormID,
        location: CellSceneLocation,
        placement: PlacedReference.Placement,
        scale: Float = 1,
        count: Int32 = 1
    ) {
        self.base = base
        self.location = location
        self.placement = placement
        self.scale = scale.isFinite && scale > 0 ? scale : 1
        self.count = max(1, count)
    }

    init?(erased: WorldStateComponentValue) {
        guard case let .spawn(value) = erased else { return nil }
        self = value
    }
}

/// The raw FormID a spawned reference is addressed by inside a built cell.
///
/// Everything below the runtime index — collision raycasts, interaction
/// metadata, the render instance sort key — addresses a placement by raw
/// `FormID`, so a generated reference needs one even though no plugin defines
/// it. The mapping is from the generated key's sequence number, which is
/// already the whole of the allocator's state, into the `0xFF` mod index.
///
/// `0xFF` is safe by construction rather than by convention: a plugin's records
/// are numbered by its position in the load order, and a load order can hold at
/// most 0xFE plugins because the index is one byte, so no plugin record can
/// ever carry it. (Bethesda's own save format uses the same index for
/// save-created references, which is a corroboration of the reasoning and not
/// its source.)
nonisolated enum SpawnedReferenceIdentity {
    /// High byte of every spawned reference's FormID.
    static let modIndex: UInt32 = 0xFF00_0000
    /// Largest sequence number that still fits in the 24-bit object ID.
    static let maximumSequence: UInt64 = 0x00FF_FFFF

    /// The FormID `key` is placed under, or nil when `key` is not a generated
    /// key or its sequence has outrun the 24-bit object ID.
    ///
    /// Running out is not a silent wrap: a wrapped sequence would alias two
    /// distinct objects onto one FormID, so the build drops the reference and
    /// counts it instead. Reaching the cap needs 16.7 million spawns in one
    /// session, which no play session produces.
    static func formID(for key: ReferenceKey) -> FormID? {
        guard case let .generated(sequence) = key, sequence <= maximumSequence else {
            return nil
        }
        return FormID(modIndex | UInt32(sequence))
    }
}
