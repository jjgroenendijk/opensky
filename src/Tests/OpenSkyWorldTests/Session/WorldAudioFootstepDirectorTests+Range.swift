// Another actor's footsteps: past their sound's output model range they start no
// voice, and they resolve against their own armatures' set and their own ground.
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
                routing: .positional,
                attenuation: AttenuationCurve(
                    minimumDistance: 150,
                    maximumDistance: 1800,
                    points: [
                        1,
                        0
                    ]
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

    @Test func anotherActorsStepUsesItsOwnArmaturesSet() throws {
        let engine = try WorldAudioDirectorFixture.makeRunningEngine()
        let director = makeDirector(engine: engine)

        director.handleActorGraphEvents(["FootFront"], gait: .walk, position: .zero)
        #expect(engine.sources.isEmpty, "the default set has no FootFront")

        director.handleActorGraphEvents(
            ["FootFront"], gait: .walk, position: .zero,
            armatures: [FormID(0x901), FormID(0x902)]
        )
        #expect(engine.sources.count == 1)
        #expect(
            director.footstepSetDescription == FootstepStore.defaultSetEditorID,
            "another actor's set leaves the player's alone"
        )
    }

    @Test func anotherActorsStepResolvesAgainstItsGround() throws {
        let engine = try WorldAudioDirectorFixture.makeRunningEngine()
        let director = makeDirector(engine: engine)
        // The fixture's snow impact names a sound the store lacks, so it plays nothing.
        director.handleActorGraphEvents(
            ["FootLeft"], gait: .walk, position: .zero, material: FormID(0x502)
        )
        #expect(engine.sources.isEmpty)
        #expect(director.groundMaterial == nil, "the player's ground is left alone")
    }

    private static let footstepModel: UInt32 = 0x777
}
