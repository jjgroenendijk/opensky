// Spawned references: objects the running game created, which no plugin
// places. A spawn is a `WorldStateComponent`, so the store journals it, the
// save writes it, and the streamer rebuilds its cell like any other mutation.
// The component carries its own cell because `ReferenceStateDelta.cell` is
// overwritten by each later write. See docs/engine/reference-identity.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData

/// One object the running game placed in the world.
///
/// Every field is what a cell build needs to synthesize a `PlacedReference`:
/// the base record to resolve a model and collision from, where it stands, and
/// how many of it there are when the base is a carryable item.
nonisolated public struct ReferenceSpawnState: WorldStateComponent, Sendable {
    /// The base record this reference places — a MISC, WEAP, ALCH and so on
    /// for a dropped item.
    public let base: FormID
    /// The cell the object exists in. Non-optional: an object with no cell is
    /// not in the world, and a build has no way to draw it.
    public let location: CellSceneLocation
    /// Position and rotation, in the same game units and radians REFR DATA
    /// uses.
    public let placement: PlacedReference.Placement
    /// Uniform scale, matching XSCL semantics.
    public let scale: Float
    /// How many of `base` the pile holds, mirroring REFR XCNT. Always at least
    /// one: a spawned reference that places nothing should not exist.
    public let count: Int32

    public static var componentKind: WorldStateComponentKind {
        .spawn
    }

    /// Normalizes on the way in, because this initializer is also the save
    /// decoder's entry point and a corrupt file must degrade rather than fail
    /// the whole load: a non-positive count becomes one, and a scale that is
    /// not a positive finite number becomes one.
    public init(
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
}

/// The raw FormID a spawned reference uses inside a built cell. Collision,
/// interaction, and render sorting address placements by raw `FormID`. The
/// sequence number maps into mod index `0xFF`, which no plugin can use: a load
/// order holds at most 0xFE plugins.
nonisolated public enum SpawnedReferenceIdentity: Sendable {
    /// High byte of every spawned reference's FormID.
    public static let modIndex: UInt32 = 0xFF00_0000
    /// Largest sequence number that still fits in the 24-bit object ID.
    public static let maximumSequence: UInt64 = 0x00FF_FFFF

    /// The FormID `key` is placed under, or nil when `key` is not generated or its
    /// sequence has outrun the 24-bit object ID. Wrapping would alias two objects,
    /// so the build drops the reference and counts it.
    public static func formID(for key: ReferenceKey) -> FormID? {
        guard case let .generated(sequence) = key, sequence <= maximumSequence else {
            return nil
        }
        return FormID(modIndex | UInt32(sequence))
    }
}
