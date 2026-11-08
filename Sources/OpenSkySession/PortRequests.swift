// Witnesses for the port requirements that take one request value.

public import OpenSkyInventory
public import OpenSkyInventoryInterface
public import OpenSkySessionInterface
public import OpenSkyWorld
public import OpenSkyWorldInterface

extension InventoryCoordinator {
    public func transfer(_ request: ContainerTransferRequest) throws -> TradeOutcome {
        try transfer(
            request.transfer, item: request.item, count: request.count, named: request.name,
            container: request.container, vendor: request.vendor, merchant: request.merchant,
            acceptingLess: request.acceptingLess
        )
    }
}

extension CellStreamer {
    @discardableResult
    public func moveActor(_ request: ActorMoveRequest) -> NPCMoveCommandResult {
        moveActor(
            request.actor, to: request.point, direct: request.direct, gait: request.gait,
            runSlowdown: request.runSlowdown, walkRunBlend: request.walkRunBlend
        )
    }
}
