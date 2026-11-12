// The walks and flights a package asks for: the queue of walks that wait for a free mover
// slot, the place each flying actor's package sends it, and the gait a follower keeps.
// See docs/engine/package-schedules.md and docs/engine/dragon-flight.md.

import OpenSkyConditions
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkyWorldConditionFunctions
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// The movement part of `PackageCoordinator`. It holds the world, not the coordinator;
/// a walk that ends at once reports through `settled`.
final class PackageMovement {
    weak let world: (any PackageWorld)?
    /// Walks that found no free mover slot, by actor.
    var waiting: [ReferenceKey: PackagePendingMove] = [:]
    /// Where each flying actor's package sends it.
    var flights: [ReferenceKey: PackageFlight] = [:]
    /// A follower's gait, which overrides its package's preferred speed.
    var paces: [ReferenceKey: LocomotionGait] = [:]
    private var nextTicket = 0
    /// A walk that failed, or a flight that is there already.
    var settled: (ReferenceKey, NPCMovementSettleReason) -> Void = { _, _ in }

    /// Flat distance from a perch within which a walk ends on the perch itself.
    static let perchReach: Float = 1536

    init(world: (any PackageWorld)?) {
        self.world = world
    }

    func forget(_ actor: ReferenceKey) {
        waiting[actor] = nil
        paces[actor] = nil
    }

    func drop(_ actor: ReferenceKey) {
        waiting.removeValue(forKey: actor)
        flights.removeValue(forKey: actor)
    }

    /// The waiting walks in the order they get a slot: scene and alias walks first, then
    /// the others in the order they asked, so no actor waits for ever.
    func queue(held: (ReferenceKey) -> Bool) -> [(actor: ReferenceKey, point: SIMD3<Float>)] {
        waiting.sorted { lhs, rhs in
            let left = held(lhs.key)
            let right = held(rhs.key)
            return left == right ? lhs.value.ticket < rhs.value.ticket : left
        }
        .map { ($0.key, $0.value.point) }
    }

    /// A move that finds every mover slot taken waits in the queue. The room check comes
    /// first, because a refused move would still pay for its path search.
    func request(
        _ actor: ReferenceKey, to point: SIMD3<Float>,
        execution: PackageOverrideExecution?, walker: ReferenceKey
    ) {
        if world?.packageActorFlies(actor) == true {
            requestFlight(actor, to: point, execution: execution)
            return
        }
        let result = world.map { world in
            world.packageMoverHasRoom(for: walker)
                ? world.movePackageActor(PackageMove(
                    walker, to: point,
                    direct: execution?.isDirect ?? false,
                    gait: paces[actor] ?? execution?.gait,
                    walkRunBlend: paces[actor] == nil ? execution?.walkRunBlend : nil
                ))
                : .busy
        }
        if result == .busy {
            let ticket = waiting[actor]?.ticket ?? nextTicket
            nextTicket = max(nextTicket, ticket + 1)
            waiting[actor] = PackagePendingMove(point: point, ticket: ticket)
        } else {
            waiting[actor] = nil
        }
        if result == .failed || result == nil {
            settled(actor, .giveUp)
        }
    }

    /// A sit procedure flies to its seat's furniture; any other walk to its point. A
    /// perched dragon whose next walk ends by its perch, as a shout from the tower,
    /// stays perched and has arrived at once.
    private func requestFlight(
        _ actor: ReferenceKey, to point: SIMD3<Float>, execution: PackageOverrideExecution?
    ) {
        let seat = execution?.runner.running.values.lazy.compactMap(\.setup.seat).first
        if
            seat == nil, let current = flights[actor], current.arrived,
            let perch = current.perchFeet,
            simd_length(SIMD2(point.x - perch.x, point.y - perch.y)) < Self.perchReach
        {
            settled(actor, .arrival)
            return
        }
        flights[actor] = PackageFlight(
            target: seat.map { .perch($0.furniture) } ?? .point(point),
            perchFeet: seat?.seat.root
        )
    }

    /// True the first time the flight reaches its target.
    func arrive(_ actor: ReferenceKey) -> Bool {
        guard flights[actor]?.arrived == false else { return false }
        flights[actor]?.arrived = true
        return true
    }
}

/// The game settings the package procedures read.
struct PackageSettings {
    /// The Guard procedure's warnings.
    let guardWarnings: GuardWarningSettings
    let sandbox: SandboxSettings
    /// How a bumped NPC steps aside.
    let bump: BumpReactionSettings
    /// Follower spacing and slowdown.
    let follow: FollowSettings

    init(_ data: PackageSessionData?) {
        guardWarnings = data?.guardWarnings ?? .vanilla
        sandbox = data?.sandboxSettings ?? .vanilla
        bump = data?.bumpSettings ?? .vanilla
        follow = data?.followSettings ?? .vanilla
    }
}
