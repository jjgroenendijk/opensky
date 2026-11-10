public import OpenSkyFactionsInterface
public import OpenSkyFormatsESM
public import OpenSkyGameData

/// What the world adapters use of `RelationshipRuntime`.
public protocol RelationshipRuntimePort {
    @discardableResult func setRank(
        _ rank: Int8,
        of observer: ReferenceKey,
        toward target: ReferenceKey,
        cells: (observer: CellSceneLocation?, target: CellSceneLocation?)
    ) -> Bool
    func state(of key: ReferenceKey) -> ActorRelationshipState
}
