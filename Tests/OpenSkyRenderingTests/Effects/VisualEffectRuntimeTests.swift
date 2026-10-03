// The visual-effect runtime: attach, follow the anchor, expire, the lasting
// de-duplication, the limit, and the membrane alpha envelope.

import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyRendering
import simd
import Testing

struct VisualEffectRuntimeTests {
    static let actor = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x700)
    static let glow = VisualEffectSpec(
        name: "Glow", artModel: "fx/glow.nif", membrane: MembraneLook(fillColor: SIMD3(1, 0, 0))
    )

    @Test func anEffectFollowsItsAnchorAndExpires() {
        var runtime = VisualEffectRuntime()
        let id = runtime.attach(Self.glow, to: .actor(Self.actor), cause: .spellHit, duration: 1)
        var transform = matrix_identity_float4x4
        transform.columns.3 = SIMD4(10, 20, 30, 1)
        let models = runtime.models { $0 == .actor(Self.actor) ? transform : nil }
        #expect(models.map(\.path) == ["fx/glow.nif"])
        #expect(models.first?.transform.columns.3 == SIMD4(10, 20, 30, 1))
        #expect(runtime.membranes { _ in .actor(0x700) }.count == 1)
        #expect(runtime.advance(0.5).isEmpty)
        #expect(runtime.advance(0.6) == [id].compactMap(\.self))
        #expect(runtime.instances.isEmpty)
    }

    @Test func anUnplacedAnchorDrawsNothing() {
        var runtime = VisualEffectRuntime()
        runtime.attach(Self.glow, to: .actor(Self.actor), cause: .race, duration: nil)
        #expect(runtime.models { _ in nil }.isEmpty)
        #expect(runtime.membranes { _ in nil }.isEmpty)
    }

    @Test func aLastingEffectIsNotDoubled() {
        var runtime = VisualEffectRuntime()
        let first = runtime.attach(Self.glow, to: .actor(Self.actor), cause: .race, duration: nil)
        let second = runtime.attach(Self.glow, to: .actor(Self.actor), cause: .race, duration: nil)
        #expect(first == second)
        #expect(runtime.instances.count == 1)
        runtime.advance(100)
        #expect(runtime.instances.count == 1)
    }

    @Test func anInvisibleSpecIsRefused() {
        var runtime = VisualEffectRuntime()
        let empty = VisualEffectSpec(name: "Nothing", artModel: nil, membrane: nil)
        #expect(runtime.attach(empty, to: .point(.zero), cause: .debug, duration: 1) == nil)
    }

    @Test func pastTheLimitTheOldestTimedEffectGoes() {
        var runtime = VisualEffectRuntime()
        runtime.attach(Self.glow, to: .actor(Self.actor), cause: .race, duration: nil)
        for index in 0 ..< VisualEffectRuntime.limit {
            runtime.attach(
                Self.glow,
                to: .point(SIMD3(Float(index), 0, 0)),
                cause: .debug,
                duration: 5
            )
        }
        #expect(runtime.instances.count == VisualEffectRuntime.limit)
        #expect(runtime.instances.first?.duration == nil)
        #expect(runtime.instances[1].anchor == .point(SIMD3(1, 0, 0)))
    }

    @Test func removalByCauseAndByAnchor() {
        var runtime = VisualEffectRuntime()
        runtime.attach(Self.glow, to: .actor(Self.actor), cause: .race, duration: nil)
        runtime.attach(Self.glow, to: .point(.zero), cause: .debug, duration: 3)
        runtime.removeAll(cause: .debug)
        #expect(runtime.instances.map(\.cause) == [.race])
        runtime.detachAll(from: .actor(Self.actor))
        #expect(runtime.instances.isEmpty)
    }

    @Test func theAlphaEnvelopeFadesInHoldsAndSettles() {
        var envelope = MembraneAlphaEnvelope()
        envelope.fadeIn = 1
        envelope.full = 1
        envelope.fadeOut = 2
        envelope.fullRatio = 1
        envelope.persistentRatio = 0.5
        #expect(envelope.alpha(at: 0.5) == 0.5)
        #expect(envelope.alpha(at: 1.5) == 1)
        #expect(envelope.alpha(at: 3) == 0.75)
        #expect(envelope.alpha(at: 10) == 0.5)
        #expect(envelope.settleTime == 4)
        #expect(MembraneLook(fillColor: .one, fill: envelope).hitDuration == 4)
    }
}
