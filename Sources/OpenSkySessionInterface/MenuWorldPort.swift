public import OpenSkyActorsInterface
public import OpenSkyAgentControl
public import OpenSkyFormatsESM
public import OpenSkySaveInterface
public import OpenSkyScriptingInterface

/// What the world adapters use of `MenuWorldAdapter`.
public protocol MenuWorldPort: AnyObject, PapyrusMenuBridge {
    func refreshTitleBackdrop()
    var playerIdentity: PlayerIdentityState? { get }
    var playerNameAndRace: (name: String, race: String) { get }
    func race(of actor: ReferenceKey) -> FormID?
    func race(ofBase base: FormID) -> FormID?
    func restorePlayerPlace(_ place: SavePlayerPlace)
    @discardableResult func setRace(of actor: ReferenceKey, to race: FormID?) -> Bool
    func teleportPlayer(_ target: AgentTeleportTarget, openingRaceMenu: Bool)
}
