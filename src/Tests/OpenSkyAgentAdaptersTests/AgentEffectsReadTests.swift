import Foundation

// `state effects` lists each live visual effect with its anchor and cause, and counts the
// decals placed in the world.

import OpenSkyAgentAdapters
import OpenSkyAgentControl
import OpenSkyFormatsESM
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkySessionTesting
import Testing

@MainActor
struct AgentEffectsReadTests {
    private let host = AgentHost()

    @Test func liveEffectsShowTheirAnchorCauseAndTimeLeft() throws {
        var runtime = VisualEffectRuntime()
        let glow = VisualEffectSpec(name: "FireGlow", artModel: "glow.nif", membrane: nil)
        let npc = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x20)
        runtime.attach(glow, to: .weapon(.player), cause: .enchantment, duration: nil)
        runtime.attach(glow, to: .node(npc, "NPC Head"), cause: .spellHit, duration: 2)
        runtime.attach(glow, to: .actor(npc), cause: .race, duration: nil)
        runtime.attach(glow, to: .point(.zero), cause: .impact, duration: 1)
        host.fakeEffects.visualEffects = runtime
        host.fakeEffects.decals = DecalRuntime()
        let world = AgentWorldAdapter(game: host, now: { Date(timeIntervalSinceReferenceDate: 0) })
        guard
            case let .object(fields) = try world.query(.effects(reference: nil)),
            case let .array(visuals) = fields["visuals"]
        else {
            Issue.record("no visuals")
            return
        }
        #expect(fields["worldDecals"] == .init(0))
        #expect(visuals.count == 4)
        #expect(visuals.first == [
            "name": "FireGlow", "anchor": "weapon of player", "cause": "enchantment",
            "secondsLeft": .null
        ])
        guard case let .object(head) = visuals[1] else { return }
        #expect(head["anchor"] == .string("node NPC Head of \(npc)"))
        #expect(head["secondsLeft"] == .init(Float(2)))
        guard case let .object(point) = visuals[3] else { return }
        #expect(point["anchor"] == "point")
    }
}
