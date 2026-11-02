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

    private func body(at position: SIMD3<Float>, mass: Float = 30, speed: Float = 0)
        -> ImpulseBody
    {
        ImpulseBody(
            key: .generated(7), reference: FormID(0x77), position: position,
            velocity: SIMD3(speed, 0, 0), mass: mass, boundingRadius: 10, kind: .clutter
        )
    }

    @Test func aBodyThatFallsIntoWaterSplashesOnce() {
        let runtime = ImpulseRuntime(world: world)
        world.bodies = [body(at: SIMD3(0, 0, 20))]
        runtime.advance()
        world.bodies = [body(at: SIMD3(0, 0, -5))]
        runtime.advance()
        runtime.advance()
        #expect(world.splashes.count == 1)
        #expect(world.splashes.first?.weight == .medium)
        #expect(world.splashes.first?.position.z == 0)
        #expect(world.splashes.first?.model == "Effects\\waterSplash.nif")
    }

    @Test func somethingThatLoadsInWaterDoesNotSplash() {
        let runtime = ImpulseRuntime(world: world)
        world.bodies = [body(at: SIMD3(0, 0, -5))]
        runtime.advance()
        #expect(world.splashes.isEmpty)
    }

    @Test func splashWeightFollowsTheMassSettings() {
        let water = WaterImpactSettings.vanilla
        #expect(WaterImpacts.weight(mass: 2, settings: water) == .silent)
        #expect(WaterImpacts.weight(mass: 6, settings: water) == .light)
        #expect(WaterImpacts.weight(mass: 40, settings: water) == .heavy)
        #expect(WaterImpacts.weight(mass: nil, settings: water) == .heavy)
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

    @Test func anExplosionPushesBodiesAndActorsAndSplashesAtTheSurface() {
        let impulses = ImpulseRuntime(world: world)
        let explosions = ExplosionRuntime(world: world)
        explosions.impulses = impulses
        world.surface = 0
        world.bodies = [body(at: SIMD3(100, 0, 10))]
        world.actors = [MeleeTarget(key: .player, feet: SIMD3(0, 150, 0))]
        let spec = ExplosionSpec(name: "Test", radius: 320, force: 60)
        explosions.detonate(spec, at: SIMD3(0, 0, 20), cause: .debug)
        #expect(world.impulses.count == 1)
        #expect(world.knocks.count == 1)
        #expect((world.knocks.first?.1.y ?? 0) > 0)
        #expect(world.splashes.first?.model == "Effects\\ExplosionSplash.nif")
    }

    @Test func aBlastUnderWaterReachesOnlyATenthOfItsRadius() {
        let radius = WaterImpacts.explosionRadius(
            320, at: SIMD3(0, 0, -50), waterHeight: 0, settings: .vanilla
        )
        #expect(abs(radius - 32) < 0.0001)
    }
}
