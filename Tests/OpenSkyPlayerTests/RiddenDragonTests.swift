// A ridden dragon: the rider's orders, the breath through the graph, Switch Target, the
// flight in the mount drive, and what a rider keeps of the input.

import OpenSkyActorPresentation
import OpenSkyFormatsESM
import OpenSkyPhysics
@testable import OpenSkyPlayer
import OpenSkyRendering
import simd
import Testing

@MainActor
private final class FakeDragonMountWorld: MountWorld {
    static let dragon = ReferenceKey.generated(200)
    static let enemy = ReferenceKey.generated(201)
    static let other = ReferenceKey.generated(202)
    var inView: ReferenceKey?
    var enemyFeet: SIMD3<Float>? = SIMD3(0, 2000, 0)
    var allowsLanding = true

    func mountCandidate(_ key: ReferenceKey) -> MountCandidate? {
        guard key == Self.dragon else { return nil }
        var candidate = MountCandidate()
        candidate.saddleBone = "SaddleBone"
        candidate.isDragon = true
        candidate.allowMountActor = 1
        return candidate
    }

    func takeMount(_ key: ReferenceKey, kind: MountKind, saddleBone: String)
        -> PlayerMountDriveStart?
    {
        PlayerMountDriveStart(
            mount: key, kind: kind, saddleBone: saddleBone, feet: SIMD3(0, 0, 0), yaw: 0,
            graph: nil, pose: PlayerPoseBuffer(), configuration: .synthetic
        )
    }

    func dismountOffset(of _: ReferenceKey) -> SIMD3<Float> {
        SIMD3(-50, 0, 65)
    }

    func lockCandidate() -> ReferenceKey? {
        inView
    }

    func allowsFlyingMountLandingRequests() -> Bool {
        allowsLanding
    }

    func switchCandidates() -> [ReferenceKey] {
        inView.map { [$0, Self.other] } ?? []
    }

    func livingActorFeet(_ key: ReferenceKey) -> SIMD3<Float>? {
        key == Self.enemy ? enemyFeet : nil
    }
}

@MainActor
struct RiddenDragonTests {
    private static let flat = MountStepWorld(
        sampleGround: { _ in nil },
        collisionQuery: { _ in [] }
    )

    private func seated() -> (MountCoordinator, FakeDragonMountWorld) {
        let world = FakeDragonMountWorld()
        let mounts = MountCoordinator(world: world)
        _ = mounts.mount(FakeDragonMountWorld.dragon)
        _ = mounts.handleRiderEvents(["pairedStop"])
        return (mounts, world)
    }

    @discardableResult
    private func fly(
        _ mounts: MountCoordinator, seconds: Float, input: (inout CameraInput) -> Void = { _ in }
    ) -> [MountCommand] {
        var commands: [MountCommand] = []
        for _ in 0 ..< Int(seconds * 30) {
            var frame = CameraInput(dt: 1.0 / 30)
            input(&frame)
            commands += mounts.advance(
                input: frame, cameraYaw: 0, weaponDrawn: false, world: Self.flat
            )
        }
        return commands
    }

    @Test func theOrdersLockAttackAndLand() {
        var orders = RiddenDragonOrders()
        let unlocked = orders.toggleAttack()
        #expect(!unlocked, "no attack without a lock")
        orders.lock(FakeDragonMountWorld.enemy)
        let attacks = orders.toggleAttack()
        #expect(attacks && orders.isAttacking)
        let enemy = SIMD3<Float>(0, 2000, 0)
        #expect(orders.goal(home: .zero, target: enemy)
            == .circle(center: enemy, radius: RiddenDragonOrders.attackRadius))
        orders.lock(FakeDragonMountWorld.enemy)
        #expect(orders.lockedTarget == nil && !orders.isAttacking)
        orders.landingRequested = true
        #expect(orders.goal(home: .zero, target: enemy) == .ground(nil))
    }

    @Test func aSeatedRiderTakesOffAndTheUseKeyOrdersTheLanding() {
        let (mounts, world) = seated()
        defer { withExtendedLifetime(world) {} }
        fly(mounts, seconds: 0.1)
        #expect(mounts.drive?.flight?.phase == .takingOff)
        fly(mounts, seconds: 6)
        #expect(mounts.drive?.flight?.phase == .cruising)
        #expect((mounts.drive?.transform.feet.z ?? 0) > 1000)
        let land = mounts.dismount()
        let cancel = mounts.dismount()
        let again = mounts.dismount()
        #expect(land == [.notify(mounts.settings.landingMessage)])
        #expect(cancel == [.notify(mounts.settings.cancelLandingMessage)])
        #expect(again == [.notify(mounts.settings.landingMessage)])
        fly(mounts, seconds: 40)
        #expect(mounts.drive?.flight?.phase == .grounded)
        #expect(mounts.phase == .riding)
        let off = mounts.dismount()
        #expect(off.last == .raiseOnPlayer(MountKind.dragon.events.riderExit))
    }

    @Test func aScriptCanRefuseTheLandingOrder() {
        let (mounts, world) = seated()
        world.allowsLanding = false
        fly(mounts, seconds: 6)
        #expect(mounts.dismount() == [.notify(mounts.settings.cannotLandMessage)])
        #expect(!mounts.dragonOrders.landingRequested)
        world.allowsLanding = true
        #expect(mounts.dismount() == [.notify(mounts.settings.landingMessage)])
    }

    @Test func jumpLocksAndASneakChangeAttacksWithBreath() {
        let (mounts, world) = seated()
        world.inView = FakeDragonMountWorld.enemy
        fly(mounts, seconds: 6)
        fly(mounts, seconds: 1.0 / 30) { $0.jump = true }
        #expect(mounts.dragonOrders.lockedTarget == FakeDragonMountWorld.enemy)
        fly(mounts, seconds: 1.0 / 30) { $0.sneak = true }
        #expect(mounts.dragonOrders.isAttacking)
        let commands = fly(mounts, seconds: 10) { $0.sneak = true }
        #expect(commands.contains(.dragonBreath(
            FakeDragonMountWorld.dragon,
            at: FakeDragonMountWorld.enemy
        )))
        world.enemyFeet = nil
        fly(mounts, seconds: 1.0 / 30) { $0.sneak = true }
        #expect(mounts.dragonOrders.lockedTarget == nil, "a dead target unlocks")
    }

    @Test func aDragonRiderShoutsAndCastsButSwingsNoWeapon() {
        var input = CameraInput(dt: 0.1)
        input.shout = true
        input.attack = true
        input.jump = true
        let spell = MountRules.riderInput(input, rightHandType: 9, kind: .dragon)
        #expect(spell.shout && spell.attack && !spell.jump)
        #expect(!MountRules.riderInput(input, rightHandType: 1, kind: .dragon).attack)
        #expect(!MountRules.riderInput(input, rightHandType: 1).shout)
    }

    @Test func theBreathInhalesThenExhalesThenCastsOnTheClipEvent() {
        var orders = RiddenDragonOrders()
        orders.lock(FakeDragonMountWorld.enemy)
        _ = orders.toggleAttack()
        let ahead = SIMD3<Float>(2000, 0, 0)
        let behind = SIMD3<Float>(-2000, 0, 0)
        func step(_ target: SIMD3<Float>, fired: Bool = false, _ delta: Float = 0.1)
            -> RiddenDragonBreathStep?
        {
            orders.advanceBreath(
                from: .zero, yaw: 0, at: target, fired: fired, deltaTime: delta
            )
        }
        #expect(step(behind) == nil, "the target must be ahead")
        #expect(step(ahead) == .inhale)
        #expect(step(ahead, 0.5) == nil)
        #expect(step(ahead, 0.5) == .exhale)
        #expect(step(ahead) == nil)
        #expect(step(ahead, fired: true) == .fire)
        #expect(orders.breathCooldown == RiddenDragonOrders.breathInterval)
        #expect(step(ahead) == nil, "the breath recovers")
    }

    @Test func switchTargetCyclesTheActorsInViewAndCallsTheAttackOff() {
        var orders = RiddenDragonOrders()
        let first = ReferenceKey.generated(1)
        let second = ReferenceKey.generated(2)
        let none = orders.switchTarget(among: [], forward: true)
        let switched = orders.switchTarget(among: [first, second], forward: true)
        #expect(!none && switched)
        #expect(orders.lockedTarget == first && orders.switchedTarget == first)
        _ = orders.toggleAttack()
        _ = orders.switchTarget(among: [first, second], forward: true)
        #expect(orders.lockedTarget == second && !orders.isAttacking)
        _ = orders.switchTarget(among: [first, second], forward: true)
        #expect(orders.lockedTarget == first, "it wraps round")
        _ = orders.switchTarget(among: [first, second], forward: false)
        #expect(orders.lockedTarget == second)
    }

    @Test func theHotkeysSwitchOnlyWhileRidingADragon() {
        let world = FakeDragonMountWorld()
        let idle = MountCoordinator(world: world)
        #expect(!idle.switchDragonTarget(forward: true))
        let (mounts, seatedWorld) = seated()
        seatedWorld.inView = FakeDragonMountWorld.enemy
        #expect(mounts.switchDragonTarget(forward: true))
        #expect(mounts.dragonOrders.switchedTarget == FakeDragonMountWorld.enemy)
        #expect(mounts.switchDragonTarget(forward: true))
        #expect(mounts.dragonOrders.switchedTarget == FakeDragonMountWorld.other)
    }
}
