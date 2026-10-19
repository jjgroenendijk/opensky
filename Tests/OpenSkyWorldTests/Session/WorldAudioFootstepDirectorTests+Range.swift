// Another actor's footsteps past their sound's output model range start no voice.
// See docs/engine/actor-graphs.md.

import Foundation
@testable import OpenSkyAudio
@testable import OpenSkyFormatsESM
import OpenSkyPhysics
@testable import OpenSkyWorld
import OpenSkyWorldFixtures
import simd
import Testing

extension WorldAudioFootstepDirectorTests {
    @Test func anotherActorsStepPastItsSoundsRangeIsSkipped() throws {
        let engine = try WorldAudioDirectorFixture.makeRunningEngine()
        let director = makeDirector(engine: engine, outputModel: Self.footstepModel)
        director.outputModels = { id in
            id == FormID(Self.footstepModel) ? OutputModelProfile(
                name: "SOMMono01800", routing: .positional,
                attenuation: AttenuationCurve(
                    minimumDistance: 150, maximumDistance: 1800, points: [1, 0]
                ),
                reverbSend: 0
            ) : nil
        }
        engine.updateListener(worldPosition: .zero, yaw: 0, pitch: 0)

        director.handleActorGraphEvents(["FootLeft"], gait: .walk, position: SIMD3(3000, 0, 0))
        #expect(engine.sources.isEmpty)
        director.handleActorGraphEvents(["FootLeft"], gait: .walk, position: SIMD3(1000, 0, 0))
        #expect(engine.sources.count == 1)
        director.handleGraphEvents(["FootLeft"], gait: .walk, position: SIMD3(3000, 0, 0))
        #expect(engine.sources.count == 2, "the player's own steps are never skipped")
    }

    private static let footstepModel: UInt32 = 0x777
}
