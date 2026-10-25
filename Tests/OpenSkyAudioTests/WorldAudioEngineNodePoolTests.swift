// One-shot positional buffers reuse their player nodes instead of building one per
// sound (WorldAudioEngineNodePool.swift). Offline rendering, as the other engine suites.

import AVFAudio
@testable import OpenSkyAudio
import simd
import Testing

@MainActor
struct WorldAudioEngineNodePoolTests {
    @discardableResult
    private func play(_ engine: WorldAudioEngine, name: String) throws -> Int {
        try engine.playPositional(
            buffer: OfflineAudioFixture.makeToneBuffer(seconds: 0.25),
            request: AudioPlayRequest(
                name: name, category: .effects, worldPosition: SIMD3(64, 0, 0)
            )
        )
    }

    @Test
    func evictedOneShotsHandTheirNodesToTheNextOnes() throws {
        let engine = try OfflineAudioFixture.makeRunningEngine()
        let first = try play(engine, name: "first")
        let firstNode = try #require(engine.sources.first { $0.id == first }?.node)
        for index in 0 ..< WorldAudioEngine.maxConcurrentSources {
            try play(engine, name: "filler \(index)")
        }
        #expect(!engine.sources.contains { $0.id == first })
        #expect(engine.engine.attachedNodes.contains(firstNode))

        let attached = engine.engine.attachedNodes.count
        for index in 0 ..< 4 {
            try play(engine, name: "more \(index)")
        }
        #expect(engine.engine.attachedNodes.count == attached)
    }

    @Test
    func aReusedNodeIsAudible() throws {
        let engine = try OfflineAudioFixture.makeRunningEngine()
        engine.updateListener(worldPosition: .zero, yaw: 0, pitch: 0)
        let first = try play(engine, name: "first")
        _ = try OfflineAudioFixture.channelRMS(engine)
        #expect(engine.stopSource(id: first))
        #expect(try OfflineAudioFixture.channelRMS(engine).reduce(0, +) < 0.001)

        try play(engine, name: "again")
        #expect(try OfflineAudioFixture.channelRMS(engine).reduce(0, +) > 0.01)
    }

    @Test
    func stoppingTheEngineReleasesPooledNodes() throws {
        let engine = try OfflineAudioFixture.makeRunningEngine()
        let first = try play(engine, name: "first")
        let node = try #require(engine.sources.first { $0.id == first }?.node)
        engine.stopSource(id: first)
        #expect(engine.bufferNodePool.idleCount == 1)

        engine.isEnabled = false
        #expect(engine.bufferNodePool.idleCount == 0)
        #expect(!engine.engine.attachedNodes.contains(node))
    }
}
