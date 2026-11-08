public import OpenSkyFormatsESM

/// What the world adapters use of `SpellCastState`.
public protocol SpellCastStatePort {
    var spell: ReferenceKey? { get }
}
