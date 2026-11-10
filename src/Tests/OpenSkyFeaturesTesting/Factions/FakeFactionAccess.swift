// Fakes of the faction seams: membership and relationship ranks kept in dictionaries,
// every call recorded.

public import OpenSkyFactionsInterface
public import OpenSkyFormatsESM
public import OpenSkyGameData

@MainActor
public final class FakeFactionAccess: FactionAccess {
    public var factions = FactionStore(plugins: [])
    public var ranks: [ReferenceKey: [ReferenceKey: Int8]] = [:]
    public private(set) var left: [ReferenceKey] = []

    public init() {}

    public func isMember(_ key: ReferenceKey, of faction: ReferenceKey) -> Bool {
        ranks[key]?[faction] != nil
    }

    public func rank(of key: ReferenceKey, in faction: ReferenceKey) -> Int8? {
        ranks[key]?[faction]
    }

    public func join(
        _ key: ReferenceKey,
        to faction: ReferenceKey,
        rank: Int8,
        in _: CellSceneLocation?
    ) -> Bool {
        ranks[key, default: [:]][faction] = rank
        return true
    }

    public func leave(_ key: ReferenceKey, from faction: ReferenceKey, in _: CellSceneLocation?)
        -> Bool
    {
        left.append(faction)
        return ranks[key]?.removeValue(forKey: faction) != nil
    }
}

@MainActor
public final class FakeRelationshipAccess: RelationshipAccess {
    public var ranks: [[ReferenceKey]: Int8] = [:]

    public init() {}

    public func rank(
        of observer: ReferenceKey,
        toward target: ReferenceKey,
        bases _: (ReferenceKey) -> ResolvedFormID?
    ) -> Int8? {
        ranks[[observer, target]]
    }

    public func setRank(
        _ rank: Int8,
        of observer: ReferenceKey,
        toward target: ReferenceKey,
        cells _: (observer: CellSceneLocation?, target: CellSceneLocation?)
    ) -> Bool {
        ranks[[observer, target]] = rank
        return true
    }
}
