// Splashes, physics hits, fast-water knockdowns, and explosion pushes through a fake
// world (docs/engine/impulses.md).

import OpenSkyCombat
import OpenSkyFormatsESM
import OpenSkyPhysics
import simd
import Testing

@MainActor
private final class FakeImpulseWorld: ImpulseWorld, ExplosionWorld {
    var bodies: [ImpulseBody] = []
    var actors: [MeleeTarget] = []
    var surface: Float? = 0
    var flow = SIMD2<Float>(0, 0)
    var size = 1
    var impulses: [BodyImpulse] = []
    var knocks: [(ReferenceKey, SIMD3<Float>)] = []
    var downs: [(ReferenceKey, SIMD3<Float>)] = []
    var damage: [ReferenceKey: Float] = [:]
    var splashes: [SplashEvent] = []

    func impulseBodies() -> [ImpulseBody] {
        bodies
    }

    func applyBodyImpulse(_ impulse: BodyImpulse) {
        impulses.append(impulse)
    }

    func impulseActors() -> [MeleeTarget] {
        actors
    }

    func waterHeight(at _: SIMD2<Float>) -> Float? {
        surface
    }

    func waterFlow(at _: SIMD2<Float>) -> SIMD2<Float>? {
        flow
    }

    func raceSize(of _: ReferenceKey) -> Int {
        size
    }

    func knockActor(_ actor: ReferenceKey, velocity: SIMD3<Float>, knockdown _: Bool) -> Bool {
        knocks.append((actor, velocity))
        return true
    }

    func isPushable(_: ReferenceKey) -> Bool {
        true
    }

    func knockDown(_ actor: ReferenceKey, from source: SIMD3<Float>, magnitude _: Float) -> Bool {
        downs.append((actor, source))
        return true
    }

    func actorHealth(of _: ReferenceKey) -> (current: Float, maximum: Float)? {
        (100, 100)
    }

    func applyPhysicsDamage(_ amount: Float, to actor: ReferenceKey) -> Bool {
        damage[actor, default: 0] += amount
        return true
    }

    func showSplash(_ splash: SplashEvent) {
        splashes.append(splash)
    }

    func explosionTargets() -> [MeleeTarget] {
        actors
    }

    func explosionViewer() -> SIMD3<Float>? {
        nil
    }

    func applyExplosionDamage(_: Float, to _: ReferenceKey) -> Bool {
        false
    }

    func playExplosionSound(_: ReferenceKey, at _: SIMD3<Float>) {}
    func startExplosionImageSpace(_: ReferenceKey, strength _: Float) {}
    func placeExplosionHazard(_: ReferenceKey, at _: SIMD3<Float>) -> Bool {
        false
    }

    func showExplosionModel(_: String, at _: SIMD3<Float>) {}
}

@MainActor
struct ImpulseRuntimeTests {
    private let world = FakeImpulseWorld()

    private func body(
        at position: SIMD3<Float>, mass: Float = 30, speed: Float = 0, fall: Float = 0
    ) -> ImpulseBody {
        ImpulseBody(
            key: .generated(7), reference: FormID(0x77), position: position,
            velocity: SIMD3(speed, 0, -fall), mass: mass, boundingRadius: 10, kind: .clutter
        )
    }

    @Test func aBodyThatFallsIntoWaterSplashesOnce() {
        let runtime = ImpulseRuntime(world: world)
        world.bodies = [body(at: SIMD3(0, 0, 20), fall: 100)]
        runtime.advance()
        world.bodies = [body(at: SIMD3(0, 0, -5), fall: 100)]
        runtime.advance()
        runtime.advance()
        #expect(world.splashes.count == 1)
        // 30 kg plus 0.05 times 100 units a second is 35, not over the heavy 35.
        #expect(world.splashes.first?.weight == .medium)
        #expect(world.splashes.first?.scale == 0.75)
        #expect(world.splashes.first?.position.z == 0)
        #expect(world.splashes.first?.model == "Effects\\waterSplash.nif")
    }

    @Test func somethingThatLoadsInWaterDoesNotSplash() {
        let runtime = ImpulseRuntime(world: world)
        world.bodies = [body(at: SIMD3(0, 0, -5))]
        runtime.advance()
        #expect(world.splashes.isEmpty)
    }

    @Test func splashWeightFollowsTheMassAndTheFallSpeed() {
        let water = WaterImpactSettings.vanilla
        #expect(WaterImpacts.weight(mass: 2, settings: water) == .silent)
        #expect(WaterImpacts.weight(mass: 6, settings: water) == .light)
        #expect(WaterImpacts.weight(mass: 6, verticalSpeed: -400, settings: water) == .medium)
        #expect(WaterImpacts.weight(mass: 40, settings: water) == .heavy)
        #expect(WaterImpacts.weight(mass: 40, leaving: true, settings: water) == .light)
        #expect(WaterImpacts.weight(mass: nil, settings: water) == .heavy)
    }

    @Test func aBodyLeavingTheWaterSplashesAtHalfItsValue() {
        let runtime = ImpulseRuntime(world: world)
        world.bodies = [body(at: SIMD3(0, 0, -5), mass: 60, fall: -10)]
        runtime.advance()
        world.bodies = [body(at: SIMD3(0, 0, 5), mass: 60, fall: -10)]
        runtime.advance()
        // (60 + 0.5) * 0.5 is 30.25: a medium splash.
        #expect(world.splashes.map(\.weight) == [.medium])
    }

    @Test func splashesAnywhereKeepTheTimerApart() {
        var tracker = SplashTracker()
        let water = WaterImpactSettings.vanilla
        func samples(z: Float) -> [WaterSample] {
            (1 ... 2).map {
                WaterSample(
                    key: .generated(UInt64($0)), position: SIMD3(0, 0, z), mass: 30,
                    waterHeight: 0, verticalSpeed: -50
                )
            }
        }
        _ = tracker.update(samples(z: 10), settings: water)
        #expect(tracker.update(samples(z: -10), deltaTime: 0.1, settings: water).count == 1)
        _ = tracker.update(samples(z: 10), deltaTime: 0.1, settings: water)
        #expect(tracker.update(samples(z: -10), deltaTime: 0.3, settings: water).count == 1)
    }

    @Test func aFastHeavyBodyHurtsAnActorOncePerContact() {
        let runtime = ImpulseRuntime(world: world)
        world.surface = nil
        world.actors = [MeleeTarget(key: .player, feet: SIMD3(0, 0, 0))]
        world.bodies = [body(at: SIMD3(10, 0, 50), mass: 60, speed: 1000)]
        runtime.advance()
        runtime.advance()
        #expect(abs((world.damage[.player] ?? 0) - 5.5) < 0.0001)
    }

    @Test func fastWaterKnocksDownAlongItsFlow() {
        let runtime = ImpulseRuntime(world: world)
        world.surface = 100
        world.flow = SIMD2(4, 0)
        world.actors = [MeleeTarget(key: .player, feet: SIMD3(0, 0, 0))]
        runtime.advance()
        runtime.advance()
        // 4 units a second passes 5 times the normal 0.75.
        #expect(world.knocks.count == 1)
        #expect(world.knocks.first?.1.x == 4)
        world.size = 3
        #expect(!WaterImpacts.knocksDown(flowSpeed: 4, raceSize: 3, settings: .vanilla))
    }

    @Test func anExplosionPushesBodiesAndKnocksDownByItsFlags() {
        let impulses = ImpulseRuntime(world: world)
        let explosions = ExplosionRuntime(world: world)
        explosions.impulses = impulses
        world.surface = 100
        world.bodies = [body(at: SIMD3(100, 0, 10))]
        world.actors = [MeleeTarget(key: .player, feet: SIMD3(0, 50, 0))]
        var spec = ExplosionSpec(name: "Test", radius: 320, force: 6)
        explosions.detonate(spec, at: SIMD3(0, 0, 20), cause: .debug)
        #expect(world.impulses.count == 1)
        #expect(world.downs.isEmpty)
        spec.knockdown = .always
        explosions.detonate(spec, at: SIMD3(0, 0, 20), cause: .debug)
        #expect(world.downs.count == 1)
        #expect(world.splashes.first?.model == "Effects\\ExplosionSplash.nif")
    }

    @Test func aBlastSplashesOnlyBelowATenthOfItsRadiusUnderTheSurface() throws {
        let shallow = WaterImpacts.explosionSplash(
            at: SIMD3(0, 0, -20), radius: 320, waterHeight: 0, settings: .vanilla
        )
        let deep = try #require(WaterImpacts.explosionSplash(
            at: SIMD3(0, 0, -50), radius: 320, waterHeight: 0, settings: .vanilla
        ))
        #expect(shallow == nil)
        #expect(abs(deep.scale - 320 / 250) < 0.0001)
    }
}
