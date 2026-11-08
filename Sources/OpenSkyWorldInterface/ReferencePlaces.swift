public import OpenSkyConditions
public import OpenSkyFormatsESM

/// Each resident reference's location, whether its cell is an interior, and its cell.
nonisolated public struct ReferencePlaces: Equatable, Sendable {
    public var locations: [ReferenceKey: ResolvedFormID] = [:]
    public var interiors: [ReferenceKey: Bool] = [:]
    public var cells: [ReferenceKey: ReferenceCell] = [:]

    public init() {}
}
