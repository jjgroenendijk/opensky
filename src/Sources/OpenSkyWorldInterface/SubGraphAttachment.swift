import OpenSkyBehavior
public import OpenSkyFormatsESM
import simd

/// Which model a running sub-graph belongs to. Graphs step in this order.
nonisolated public enum SubGraphID: Hashable, Comparable, Sendable {
    /// A visual effect, by its instance id.
    case effect(Int)
    /// An armour addon model an actor wears, by the addon's form ID.
    case armorAddon(ReferenceKey, armature: UInt32)
}

nonisolated public enum SubGraphAnchor: Equatable, Sendable {
    case actor(ReferenceKey)
    /// An effect at a point, such as an explosion. No actor's events reach it.
    case point(SIMD3<Float>)
}
