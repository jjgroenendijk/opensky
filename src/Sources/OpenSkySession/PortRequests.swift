// Witnesses for the port requirements that take one request value.

public import OpenSkySessionInterface
public import OpenSkyWorld
public import OpenSkyWorldInterface

extension CellStreamer {
    @discardableResult
    public func moveActor(_ request: ActorMoveRequest) -> NPCMoveCommandResult {
        moveActor(
            request.actor, to: request.point, direct: request.direct, gait: request.gait,
            runSlowdown: request.runSlowdown, walkRunBlend: request.walkRunBlend
        )
    }
}
