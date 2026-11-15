// A lightning controller's bolt: the hidden shape below its node gives the place and the
// effect shader, and a sequence or the controller's own interpolators give the tracks.
// See docs/rendering/particles.md#lightning.

import Foundation
@testable import OpenSkyFormatsMesh
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import simd
import Testing

@Suite(.tags(.parser))
struct NIFLightningTests {
    private static let strings = ["mIdle", "Generation", "ArcOffset", "mBegin", "Mutation"]

    private static func controller(interpolators: [Int32] = [], flags: UInt16 = 0x28) -> Data {
        NIFParticleParameterFixture.lightningController(
            targetRef: 1, subdivisions: 4, branches: 2, length: 512, width: 16,
            interpolators: interpolators, flags: flags
        )
    }

    /// Sequence "mIdle" (block 7) feeds generation and arc offset; "mBegin" (block 8)
    /// feeds only a mutation.
    private static func sequencedFile() throws -> NIFFile {
        try NIFFile(data: NIFParticleParameterFixture.lightningFile(
            controller: controller(),
            extraBlocks: [
                NIFFixture.Block(
                    "NiBoolInterpolator", NIFParticleParameterFixture.boolInterpolator(true)
                ),
                NIFFixture.Block(
                    "NiFloatInterpolator", NIFParticleParameterFixture.floatInterpolator(30)
                ),
                NIFFixture.Block("NiControllerSequence", NIFParticleParameterFixture.sequence(
                    name: 0, timing: (0, 2), controller: 3, links: [(5, 1), (6, 2)]
                )),
                NIFFixture.Block("NiControllerSequence", NIFParticleParameterFixture.sequence(
                    name: 3, timing: (2, 1), controller: 3, links: [(5, 4)]
                ))
            ],
            strings: strings
        ))
    }

    @Test func theBoltSitsAtTheHiddenShapeBelowItsNodeAndTakesItsShader() throws {
        let bolt = try #require(try Self.sequencedFile().particleSystems().first)
        #expect(bolt.worldTransform.columns.3.z == 10)
        #expect(bolt.shaderPropertyRef == 4)
        #expect(bolt.effectShader != nil)
        #expect(bolt.lightning?.length == 512)
    }

    @Test func aSequenceFeedsTheTracksByInterpolatorID() throws {
        let lightning = try #require(try Self.sequencedFile().particleSystems().first?.lightning)
        let idle = try #require(lightning.sequenceTracks["midle"])
        #expect(idle.generation == [NIFKey(time: 0, value: true)])
        #expect(idle.arcOffset == [NIFKey(time: 0, value: 30)])
        #expect(idle.timing.cycle == .loop)
        #expect(idle.timing.stopTime == 2)
        #expect(lightning.sequenceTracks["mbegin"]?.mutation == [NIFKey(time: 0, value: true)])
        #expect(lightning.sequenceTracks["mbegin"]?.generation.isEmpty == true)
    }

    /// The default sequence is one that keys the generation, because only such a
    /// sequence can show a bolt.
    @Test func theDefaultTracksComeFromASequenceThatKeysTheGeneration() throws {
        let lightning = try #require(try Self.sequencedFile().particleSystems().first?.lightning)
        #expect(lightning.tracks == lightning.sequenceTracks["midle"])
        #expect(lightning.isKeyed)
        #expect(lightning.animatesArcOffset)
    }

    @Test func aControllerNoSequenceFeedsUsesItsOwnInterpolators() throws {
        let file = try NIFFile(data: NIFParticleParameterFixture.lightningFile(
            controller: Self.controller(interpolators: [5], flags: 0x8),
            extraBlocks: [NIFFixture.Block(
                "NiBoolInterpolator", NIFParticleParameterFixture.boolInterpolator(true)
            )]
        ))
        let lightning = try #require(try file.particleSystems().first?.lightning)
        #expect(lightning.tracks?.generation == [NIFKey(time: 0, value: true)])
        #expect(lightning.sequenceTracks.isEmpty)
    }

    @Test func aControllerWithNoGenerationTrackIsNotKeyed() throws {
        let file = try NIFFile(data: NIFParticleParameterFixture.lightningFile(
            controller: Self.controller()
        ))
        let lightning = try #require(try file.particleSystems().first?.lightning)
        #expect(lightning.tracks == nil)
        #expect(!lightning.isKeyed)
    }

    @Test func aTrackReplacesTheStoredFieldAtItsTime() throws {
        var lightning = try #require(try Self.sequencedFile().particleSystems().first?.lightning)
        var tracks = LightningTracks(timing: ControllerTiming(
            cycle: .clamp, frequency: 1, phase: 0, startTime: 0, stopTime: 1
        ))
        tracks.length = [NIFKey(time: 0, value: 100), NIFKey(time: 1, value: 200)]
        tracks.arcOffset = [NIFKey(time: 0, value: 5)]
        lightning.apply(tracks, at: 0.5)
        #expect(lightning.length == 150)
        #expect(lightning.arcOffset == 5)
        #expect(lightning.width == 16, "an empty track keeps the stored field")
        lightning.animatesArcOffset = false
        lightning.arcOffset = 20
        lightning.apply(tracks, at: 0.5)
        #expect(lightning.arcOffset == 20, "the arc offset moves only with the animate flag")
    }

    @Test func theReportListsEachFeedOfTheController() throws {
        let report = try #require(try Self.sequencedFile().lightningReports().first)
        #expect(report.controller == 3)
        #expect(report.targetType == "NiNode")
        #expect(report.feeds.map(\.id) == ["ArcOffset", "Generation", "Mutation"])
        #expect(report.feeds.map(\.sequence) == ["mIdle", "mIdle", "mBegin"])
    }
}
