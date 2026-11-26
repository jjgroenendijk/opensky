// A towed cart on its tow line: it lags a horse that starts, rolls on after one that stops,
// stays within the hitch's play, and rolls back on a slope. See docs/engine/vehicles.md.

@testable import OpenSkyActorPresentation
import OpenSkyFormatsESM
import OpenSkyWorldState
import simd
import Testing

struct VehicleTowDynamicsTests {
    private static let horse = ReferenceKey.plugin(name: "test.esm", objectID: 1)
    private static let cart = ReferenceKey.plugin(name: "test.esm", objectID: 2)
    private static let frame: Float = 1.0 / 60

    private static func towed(ground: @escaping (SIMD3<Float>) -> Float? = { _ in 0 })
        -> VehicleCore
    {
        var core = VehicleCore()
        core.tow(
            cart, by: horse,
            followerPose: ReferenceTransformOverride(position: [0, -200, 0]),
            carrierPose: ReferenceTransformOverride(position: .zero),
            ground: ground
        )
        return core
    }

    /// Each frame's gap from the cart to the horse, the cart's y, and where the horse ended.
    private struct Drive {
        var gaps: [Float] = []
        var cartY: [Float] = []
        var end: Float = 0
    }

    /// Steps the horse along +Y at `speed` for `seconds`.
    private static func drive(
        _ core: inout VehicleCore, from start: Float, speed: Float, seconds: Float,
        ground: (SIMD3<Float>) -> Float? = { _ in 0 }
    ) -> Drive {
        var horseY = start
        var drive = Drive()
        for _ in 0 ..< Int(seconds / frame) {
            horseY += speed * frame
            let horse = ReferenceTransformOverride(position: [0, horseY, 0])
            let poses = core.advance(base: { _ in horse }, ground: ground, dt: frame)
            let cart = poses[Self.cart]?.position ?? .zero
            drive.gaps.append(horseY - cart.y)
            drive.cartY.append(cart.y)
        }
        drive.end = horseY
        return drive
    }

    @Test func theCartLagsAHorseThatStartsAndStaysWithinThePlay() {
        var core = Self.towed()
        _ = Self.drive(&core, from: 0, speed: 0, seconds: 0.1)
        let run = Self.drive(&core, from: 0, speed: 150, seconds: 1)
        let play = VehicleTowSpring.vanilla.play
        #expect(run.gaps.contains { $0 > 200.5 }, "the cart falls behind at the start")
        #expect(run.gaps.allSatisfy { $0 <= 200 + play + 0.01 && $0 >= 200 - play - 0.01 })
    }

    @Test func theCartRollsOnAfterTheHorseStopsThenSettles() {
        var core = Self.towed()
        _ = Self.drive(&core, from: 0, speed: 0, seconds: 0.1)
        let run = Self.drive(&core, from: 0, speed: 150, seconds: 2)
        let stopped = Self.drive(&core, from: run.end, speed: 0, seconds: 3)
        let atStop = run.cartY.last ?? 0
        #expect((stopped.cartY.max() ?? 0) > atStop + 0.5, "the cart rolls on after the stop")
        #expect(abs((stopped.gaps.last ?? 0) - 200) < 1, "the line settles to its length")
    }

    @Test func aStandingCartMakesNoGroundSearchAndMovesAgainWithItsHorse() {
        var core = Self.towed()
        _ = Self.drive(&core, from: 0, speed: 0, seconds: 1)
        var searches = 0
        let counted: (SIMD3<Float>) -> Float? = { _ in
            searches += 1
            return 0
        }
        let standing = Self.drive(&core, from: 0, speed: 0, seconds: 0.5, ground: counted)
        #expect(searches == 0)
        #expect(abs((standing.gaps.last ?? 0) - 200) < 0.01)
        let moving = Self.drive(&core, from: 0, speed: 150, seconds: 0.5, ground: counted)
        #expect(searches > 0)
        #expect((moving.cartY.last ?? 0) > -190, "the cart starts 200 behind the horse")
    }

    /// The tow line chatters at the end of its play on a slope, and the cart still rests.
    @Test func aCartStandingOnASlopeRestsToo() {
        let slope: (SIMD3<Float>) -> Float? = { $0.y * 0.2 }
        var core = Self.towed(ground: slope)
        _ = Self.drive(&core, from: 0, speed: 0, seconds: 5, ground: slope)
        var searches = 0
        let counted: (SIMD3<Float>) -> Float? = { point in
            searches += 1
            return slope(point)
        }
        _ = Self.drive(&core, from: 0, speed: 0, seconds: 0.5, ground: counted)
        #expect(searches == 0)
    }

    @Test func aCartBelowItsHorseOnASlopeRollsBackALittle() {
        let slope: (SIMD3<Float>) -> Float? = { $0.y * 0.2 }
        var core = Self.towed(ground: slope)
        let rest = Self.drive(&core, from: 0, speed: 0, seconds: 3, ground: slope)
        let gap = rest.gaps.last ?? 0
        #expect(gap > 200.5 && gap <= 200 + VehicleTowSpring.vanilla.play + 0.01)
    }

    @Test func withoutATimeStepTheCartKeepsTheLinkDistance() throws {
        var core = Self.towed()
        let ahead = ReferenceTransformOverride(position: [0, 100, 0])
        let poses = core.advance(base: { _ in ahead }, ground: { _ in 0 })
        let cart = try #require(poses[Self.cart])
        #expect(simd_length(cart.position - [0, -100, 0]) < 0.01)
    }
}
