// A sandbox's furniture activity: after another activity the actor asks the world for
// a free seat in its area, walks to it, sits or lies there for the activity's time,
// and gets up. Creation Kit wiki "Sandbox (Procedure)"; docs/engine/sandbox.md.

import OpenSkyWorldInterface
import simd

/// Where a sandbox may look for furniture, and which kinds it may use.
nonisolated public struct SandboxSeatRequest: Equatable, Sendable {
    public let center: SIMD3<Float>
    public let radius: Float
    /// Below and above the centre, as `fSandboxCylinderBottom` and `...Top`.
    public let height: ClosedRange<Float>
    /// Allow Sitting: sit and lean markers.
    public let sits: Bool
    /// Allow Sleeping: bed markers.
    public let sleeps: Bool
    /// Allow Special Furniture: crafting stations and the like.
    public let usesSpecialFurniture: Bool

    public init(
        center: SIMD3<Float>, radius: Float, height: ClosedRange<Float>,
        sits: Bool, sleeps: Bool, usesSpecialFurniture: Bool
    ) {
        self.center = center
        self.radius = radius
        self.height = height
        self.sits = sits
        self.sleeps = sleeps
        self.usesSpecialFurniture = usesSpecialFurniture
    }

    /// Whether this sandbox may use the seat: inside the area, of an allowed type, and
    /// not on furniture that is Ignored By Sandbox.
    public func admits(_ seat: FurnitureSeat) -> Bool {
        let offset = seat.position - center
        guard
            simd_length(SIMD2(offset.x, offset.y)) <= radius,
            height.contains(offset.z),
            !seat.rules.ignoredBySandbox
        else { return false }
        return seat.animationType == FurnitureSeat.sleepAnimation ? sleeps : sits
    }
}

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
