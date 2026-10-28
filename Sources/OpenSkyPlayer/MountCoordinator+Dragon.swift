// A ridden dragon: the rider does not steer it, but locks or switches a target, orders
// the attack, and orders the landing. The orders live in `RiddenDragonOrders`; the
// flight in the mount drive. See docs/engine/dragon-flight.md#riding.

import Foundation
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
        let fired = step.graph.contains {
            $0.caseInsensitiveCompare(DragonFlightGraphNames.breathFire) == .orderedSame
        }
        let breath = dragonOrders.advanceBreath(
            from: pose.feet, yaw: pose.yaw, at: target, fired: fired, deltaTime: input.dt
        )
        switch breath {
        case .inhale: drive.raiseGraphEvent(DragonFlightGraphNames.breathStart)
        case .exhale: drive.raiseGraphEvent(DragonFlightGraphNames.breathRelease)
        case .fire:
            if let locked = dragonOrders.lockedTarget {
                commands.append(.dragonBreath(drive.mount, at: locked))
            }
        case nil: break
        }
        return commands
    }

    /// Switch Target, the hotkeys 1 (back) and 2 (forward) while a dragon flies.
    /// - Returns: false when the player rides no dragon, so the hotkey uses its favourite.
    public func switchDragonTarget(forward: Bool) -> Bool {
        guard let drive, drive.kind == .dragon, phase == .riding else { return false }
        _ = dragonOrders.switchTarget(among: world?.switchCandidates() ?? [], forward: forward)
        return true
    }

    /// The land order, or calling it off. A dragon in its approach clip lands anyway.
    func orderLanding(_ drive: PlayerMountDrive) -> [MountCommand] {
        guard dragonOrders.landingRequested else {
            guard world?.allowsFlyingMountLandingRequests() ?? true else {
                return [.notify(settings.cannotLandMessage)]
            }
            dragonOrders.landingRequested = true
            return [.notify(settings.landingMessage)]
        }
        guard drive.flight?.isApproaching != true else { return [] }
        dragonOrders.landingRequested = false
        return [.notify(settings.cancelLandingMessage)]
    }
}

extension MountCoordinator {
    /// A forced order for the ridden dragon, as agent control sends it: any landing order
    /// asks for the rider's landing, take-off calls it off so the dragon flies again.
    public func orderDragon(_ order: DragonFlightOrder) -> [MountCommand] {
        guard let drive, drive.kind == .dragon, phase == .riding else { return [] }
        let wantsLanding = order != .takeOff
        guard dragonOrders.landingRequested != wantsLanding else { return [] }
        return orderLanding(drive)
    }
}
