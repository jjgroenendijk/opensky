public import OpenSkyAgentControl
public import OpenSkyGameData
public import OpenSkySaveInterface

/// What the world adapters use of `AgentWorldAdapter`.
public protocol AgentWorldPort: AnyObject {
    associatedtype AgentTeleportJob: AgentTeleportJobPort
    var dataRoot: GameDataRoot? { get }
    var isWorldReady: Bool { get }
    func viewJob(_ target: AgentViewTarget) throws(AgentFailure) -> AgentTeleportJob
    func notReady() -> AgentFailure
    func teleportJob(to target: AgentTeleportTarget) throws(AgentFailure) -> AgentTeleportJob
    func teleportJob(to place: SavePlayerPlace) throws(AgentFailure) -> AgentTeleportJob
}
