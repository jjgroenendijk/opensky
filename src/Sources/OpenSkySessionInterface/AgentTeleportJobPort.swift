public import OpenSkyAgentControl

/// What the world adapters use of `AgentTeleportJob`.
public protocol AgentTeleportJobPort: AnyObject {
    var wait: AgentWait { get }
}
