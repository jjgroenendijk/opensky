// A ridden dragon: the rider does not steer it, but locks a target, orders the attack,
// and orders the landing. The orders live in `RiddenDragonOrders`; the flight in the
// mount drive. See docs/engine/dragon-flight.md#riding.

import OpenSkyActorPresentation
import OpenSkyRendering
import simd

extension MountCoordinator {
    /// One step of a seated rider on a dragon: jump locks, a sneak change attacks, and
    /// the dragon flies to what the orders ask.
    func advanceDragon(
        _ drive: PlayerMountDrive, input: CameraInput, world stepWorld: MountStepWorld
    ) -> [MountCommand] {
        if input.jump {
            dragonOrders.lock(world?.lockCandidate())
        }
        if let last = dragonOrders.lastSneak, last != input.sneak {
            _ = dragonOrders.toggleAttack()
        }
        dragonOrders.lastSneak = input.sneak
        let target = dragonOrders.lockedTarget.flatMap { world?.livingActorFeet($0) }
        if dragonOrders.lockedTarget != nil, target == nil {
            dragonOrders.lock(nil)
        }
        let home = dragonOrders.home ?? drive.transform.feet
        let step = drive.fly(
            toward: dragonOrders.goal(home: home, target: target), deltaTime: input.dt,
            world: stepWorld
        )
        let pose = drive.transform
        var commands: [MountCommand] = [
            .steerMount(drive.mount, feet: pose.feet, yaw: pose.yaw),
            .reportMountEvents(drive.mount, step.graph)
        ]
        if
            let locked = dragonOrders.lockedTarget,
            dragonOrders.breathes(from: pose.feet, at: target, deltaTime: input.dt)
        {
            commands.append(.dragonBreath(drive.mount, at: locked))
        }
        return commands
    }

    /// The land order, or calling it off. A dragon in its approach clip lands anyway.
    func orderLanding(_ drive: PlayerMountDrive) -> [MountCommand] {
        guard dragonOrders.landingRequested else {
            dragonOrders.landingRequested = true
            return [.notify(settings.landingMessage)]
        }
        guard drive.flight?.isApproaching != true else { return [] }
        dragonOrders.landingRequested = false
        return [.notify(settings.cancelLandingMessage)]
    }
}

extension MountCoordinator {
    /// A forced order for the ridden dragon, as agent control sends it: land asks for the
    /// landing, take-off calls it off so the dragon flies again.
    public func orderDragon(_ order: DragonFlightOrder) -> [MountCommand] {
        guard let drive, drive.kind == .dragon, phase == .riding else { return [] }
        let wantsLanding = order == .land
        guard dragonOrders.landingRequested != wantsLanding else { return [] }
        return orderLanding(drive)
    }
}
