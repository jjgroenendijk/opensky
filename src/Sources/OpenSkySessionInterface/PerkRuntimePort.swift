public import OpenSkyGameData
public import OpenSkyProgressionInterface

/// What the world adapters use of `PerkRuntime`.
public protocol PerkRuntimePort: PerkAccess {
    func ownedPerks(of holder: ActorValueHolder) -> [ResolvedPerk]
    var perks: PerkStore { get }
}
