public import OpenSkyFactionsInterface
public import OpenSkyFormatsESM
public import OpenSkyGameData

/// What the world adapters use of `RelationshipRuntime`.
public protocol RelationshipRuntimePort {
    @discardableResult func setRank(
        _ rank: Int8,
        of observer: ReferenceKey,
        toward target: ReferenceKey,
        in cell: CellSceneLocation?,
        targetCell: CellSceneLocation?
    ) -> Bool
    func state(of key: ReferenceKey) -> ActorRelationshipState
}

/// The default arguments a protocol requirement cannot carry.
extension RelationshipRuntimePort {
    @discardableResult public func setRank(
        _ rank: Int8,
        of observer: ReferenceKey,
        toward target: ReferenceKey,
        targetCell: CellSceneLocation?
    ) -> Bool {
        setRank(rank, of: observer, toward: target, in: nil, targetCell: targetCell)
    }

    @discardableResult public func setRank(
        _ rank: Int8,
        of observer: ReferenceKey,
        toward target: ReferenceKey,
        in cell: CellSceneLocation?
    ) -> Bool {
        setRank(rank, of: observer, toward: target, in: cell, targetCell: nil)
    }

    @discardableResult public func setRank(
        _ rank: Int8,
        of observer: ReferenceKey,
        toward target: ReferenceKey
    ) -> Bool {
        setRank(rank, of: observer, toward: target, in: nil, targetCell: nil)
    }
}
