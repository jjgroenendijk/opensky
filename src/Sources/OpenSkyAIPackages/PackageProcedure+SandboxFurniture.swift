// A sandbox's furniture activity: after another activity the actor asks the world for
// a free seat in its area, walks to it, sits or lies there for the activity's time,
// and gets up. Creation Kit wiki "Sandbox (Procedure)"; docs/engine/sandbox.md.

import OpenSkyWorldInterface
import simd

nonisolated extension PackageProcedureMachine {
    /// The wiki drops the chance of the type just used to zero, so a sandbox never
    /// picks furniture twice in a row.
    var seeksSeatNext: Bool {
        guard let sandboxSetup = setup.sandbox, sandboxSetup.sits || sandboxSetup.sleeps else {
            return false
        }
        return !(sandbox.lastActivity.map(Self.isSeatActivity) ?? false)
    }

    var seatRequest: SandboxSeatRequest {
        let sandboxSetup = setup.sandbox ?? PackageSandboxSetup(settings: .vanilla, start: center)
        let settings = sandboxSetup.settings
        return SandboxSeatRequest(
            center: center, radius: radius,
            height: settings.cylinderBottom ... max(settings.cylinderBottom, settings.cylinderTop),
            sits: sandboxSetup.sits, sleeps: sandboxSetup.sleeps,
            usesSpecialFurniture: sandboxSetup.usesSpecialFurniture
        )
    }

    /// Asks the world for a seat; `handleSeatOffer` gets the answer.
    mutating func seekSeat() -> [PackageProcedureCommand] {
        state = .ready
        return [.seekSeat(seatRequest)]
    }

    /// Walks to the offered seat, or wanders when there is none.
    mutating func handleSeatOffer(_ seat: PackageSeat?) -> [PackageProcedureCommand] {
        guard kind == .sandbox, state == .ready else { return [] }
        guard let seat else {
            return move(to: nextWanderPoint())
        }
        sandbox.seat = seat
        return move(to: seat.seat.root)
    }

    /// At the seat: sit down for the activity's time, unless a meal is due first.
    mutating func sitInSandboxSeat(_ seat: PackageSeat) -> [PackageProcedureCommand] {
        guard !mealIsDue else {
            return leaveSandboxSeat() + beginSandboxActivity(.eatStanding)
        }
        return beginSandboxActivity(Self.activity(of: seat)) + [.sit]
    }

    /// Gives the seat back, sat in or only reserved.
    mutating func leaveSandboxSeat() -> [PackageProcedureCommand] {
        guard let seat = sandbox.seat else { return [] }
        sandbox.seat = nil
        return [.endActivity(Self.activity(of: seat))]
    }

    /// A bed is the bed activity, a chair sitting, and a lean or anything else furniture.
    static func activity(of seat: PackageSeat) -> SandboxActivity {
        switch seat.seat.animationType {
        case FurnitureSeat.sleepAnimation: .sleeping
        case FurnitureSeat.sitAnimation: .sitting
        default: .furniture
        }
    }

    static func isSeatActivity(_ activity: SandboxActivity) -> Bool {
        activity == .sitting || activity == .sleeping || activity == .furniture
    }
}
