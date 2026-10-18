@testable import OpenSkyActorPresentation
@testable import OpenSkyFormatsCore
import simd
import Testing

struct ActorPoseBoundsTests {
    /// A seated actor leans its head forward, out of the head's narrow bind-pose box.
    @Test func holdsAHeadThatLeansOutOfItsBindBox() throws {
        let head = ModelBounds(min: SIMD3(-9, -9, 110), max: SIMD3(9, 10, 132))
        let body = ModelBounds(min: SIMD3(-60, -20, 0), max: SIMD3(60, 20, 128))
        let box = try #require(ActorPoseBounds.containing([head, body]))
        let leaningHead = SIMD3<Float>(0, 45, 95)
        #expect(all(leaningHead .>= box.min) && all(leaningHead .<= box.max))
    }

    /// Lying down turns the body's height onto a horizontal axis.
    @Test func holdsTheBodyTurnedOntoItsSide() throws {
        let body = ModelBounds(min: SIMD3(-60, -20, 0), max: SIMD3(60, 20, 128))
        let box = try #require(ActorPoseBounds.containing([body]))
        #expect(box.min.y <= -128 && box.max.x >= 128)
    }

    @Test func isNilWithoutParts() {
        #expect(ActorPoseBounds.containing([]) == nil)
    }
}
