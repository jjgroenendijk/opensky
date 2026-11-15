// The lightning bolt tree: its size per depth, its two crossed ribbons, its alpha, and
// when the tracks grow a new bolt. See docs/rendering/particles.md#lightning.

@testable import OpenSkyFormatsMesh
@testable import OpenSkyRendering
import simd
import Testing

struct LightningBoltTests {
    private static let loop = ControllerTiming(
        cycle: .loop, frequency: 1, phase: 0, startTime: 0, stopTime: 1
    )

    /// A straight bolt along +Y unless a test sets an arc offset.
    private static func parameters(
        subdivisions: Int = 3, branches: Int = 0, generation: [NIFKey<Bool>]? = nil
    ) -> ParticleLightning {
        var lightning = ParticleLightning(
            subdivisions: subdivisions, branches: branches, length: 512, width: 16
        )
        var tracks = LightningTracks(timing: loop)
        tracks.generation = generation ?? [NIFKey(time: 0, value: true)]
        lightning.tracks = tracks
        return lightning
    }

    private static func moment(
        _ values: ParticleLightning, generation: UInt64 = 0, mutation: UInt64 = 0
    ) -> LightningBolt.Moment {
        LightningBolt.Moment(values: values, generation: generation, mutation: mutation, isOn: true)
    }

    @Test func theMainBoltHasTwoToTheSubdivisionsSegmentsAlongPlusY() throws {
        let bolt = LightningBolt(parameters: Self.parameters(), seed: 1)
        let main = try #require(bolt.branches(Self.moment(bolt.parameters)).first)
        #expect(main.points.count == 9)
        #expect(simd_length(main.points[0]) < 1e-5)
        #expect(simd_distance(main.points[8], [0, 512, 0]) < 1e-3)
        #expect(main.width == 16)
    }

    @Test func aBendMovesPointsSidewaysOnlyAndLeavesBothEnds() throws {
        var values = Self.parameters(subdivisions: 4)
        values.arcOffset = 40
        let bolt = LightningBolt(parameters: values, seed: 3)
        let main = try #require(bolt.branches(Self.moment(values)).first)
        for (index, point) in main.points.enumerated() {
            #expect(abs(point.y - 512 * Float(index) / 16) < 1e-3)
        }
        #expect(main.points[0].x == 0 && main.points[16].x == 0)
        // The middle point takes the whole arc offset, in a random direction.
        #expect(abs(simd_length(SIMD2(main.points[8].x, main.points[8].z)) - 40) < 1e-3)
        // A quarter point moves half as far from the middle of its two neighbours.
        let between = (main.points[0] + main.points[8]) * 0.5
        let quarter = main.points[4] - between
        #expect(abs(simd_length(SIMD2(quarter.x, quarter.z)) - 20) < 1e-3)
    }

    @Test func aChildIsHalfAsLongOneSubdivisionShorterAndNarrower() {
        var values = Self.parameters(subdivisions: 3, branches: 2)
        values.childWidthMultiplier = 0.5
        let bolt = LightningBolt(parameters: values, seed: 5)
        let branches = bolt.branches(Self.moment(values))
        // Two children of the main bolt, each with one child of its own.
        #expect(branches.map(\.points.count) == [9, 5, 3, 5, 3])
        let child = branches[1]
        #expect(abs(child.points[4].y - child.points[0].y - 256) < 1e-3)
        #expect(child.width == 8)
        #expect(!child.isMain)
        // It starts at the middle of a segment in the main bolt's first half.
        let step: Float = 512 / 8
        let offset = child.points[0].y / step
        #expect(abs(offset - offset.rounded(.down) - 0.5) < 1e-4)
        #expect(child.points[0].y < 256)
        let grandchild = branches[2]
        #expect(abs(grandchild.points[2].y - grandchild.points[0].y - 128) < 1e-3)
        #expect(grandchild.width == 4)
    }

    @Test func theLengthVariationShrinksWithTheSquareOfTheDepth() {
        var values = Self.parameters(subdivisions: 2, branches: 1)
        values.lengthVariation = 64
        let bolt = LightningBolt(parameters: values, seed: 9)
        let branches = bolt.branches(Self.moment(values))
        let length = { (branch: LightningBolt.Branch) in
            (branch.points.last?.y ?? 0) - (branch.points.first?.y ?? 0)
        }
        #expect(abs(length(branches[0]) - 512) <= 64)
        #expect(abs(length(branches[1]) - 256) <= 16)
    }

    @Test func eachSegmentIsTwoCrossedQuadsWithVAlongTheBolt() {
        let branch = LightningBolt.Branch(
            points: [[0, 0, 0], [0, 10, 0], [0, 20, 0]], width: 4, fades: false, isMain: false
        )
        let quads = LightningBolt.quads(branch)
        #expect(quads.count == 4)
        #expect(quads.map(\.side) == [[1, 0, 0], [0, 0, 1], [1, 0, 0], [0, 0, 1]])
        #expect(quads[0].along == [0, 0.5] && quads[2].along == [0.5, 1])
        #expect(quads.allSatisfy { $0.width == 4 })
    }

    @Test func theAlphaIsZeroAtTheFarEndAndAtTheStartOfTheMainBolt() {
        let points: [SIMD3<Float>] = [[0, 0, 0], [0, 1, 0], [0, 2, 0], [0, 3, 0], [0, 4, 0]]
        let alpha = { (fades: Bool, isMain: Bool) -> [Float] in
            let quads = LightningBolt.quads(LightningBolt.Branch(
                points: points, width: 1, fades: fades, isMain: isMain
            ))
            return stride(from: 0, to: quads.count, by: 2).map { quads[$0].alpha.x }
                + [quads[quads.count - 1].alpha.y]
        }
        #expect(alpha(false, false) == [1, 1, 1, 1, 0])
        #expect(alpha(false, true) == [0, 1, 1, 1, 0])
        // A fading bolt loses alpha with the square of the way along it.
        let fading: [Float] = [1, 0.9375, 0.75, 0.4375, 0]
        #expect(alpha(true, false) == fading)
    }

    @Test func noBoltShowsWhileTheGenerationIsOffOrUnkeyed() {
        let keys = [NIFKey(time: 0, value: false), NIFKey(time: 0.5, value: true)]
        let bolt = LightningBolt(parameters: Self.parameters(generation: keys), seed: 1)
        #expect(bolt.quads(at: 0.25).isEmpty)
        #expect(bolt.quads(at: 0.75).count == 16)
        var unkeyed = Self.parameters()
        unkeyed.tracks = nil
        #expect(LightningBolt(parameters: unkeyed, seed: 1).quads(at: 0.75).isEmpty)
    }

    @Test func eachTurnToOnGrowsANewTreeAndAMutationKeepsTheTree() throws {
        var values = Self.parameters(
            subdivisions: 3, branches: 2,
            generation: [NIFKey(time: 0, value: false), NIFKey(time: 0.5, value: true)]
        )
        values.arcOffset = 30
        values.branchVariation = 2
        values.tracks?.mutation = [NIFKey(time: 0, value: false), NIFKey(time: 0.75, value: true)]
        let bolt = LightningBolt(parameters: values, seed: 11)
        let first = try #require(bolt.moment(at: 0.6))
        let mutated = try #require(bolt.moment(at: 0.8))
        let next = try #require(bolt.moment(at: 1.6))
        #expect(first.generation == mutated.generation)
        #expect(first.mutation != mutated.mutation)
        #expect(next.generation != first.generation)
        // The same time always gives the same bolt.
        #expect(bolt.quads(at: 0.6) == bolt.quads(at: 0.6))
        // A mutation keeps where the children start, and moves the points.
        let before = bolt.branches(first)
        let after = bolt.branches(mutated)
        #expect(before.count == after.count)
        #expect(before.map(\.points.count) == after.map(\.points.count))
        #expect(before[0].points != after[0].points)
    }

    @Test func trackChangesAreCountedAcrossLoops() {
        let keys = [NIFKey(time: 0, value: false), NIFKey(time: 0.5, value: true)]
        let count = { (seconds: Float, cycle: ControllerCycle) in
            LightningTrackCount.changes(
                keys,
                timing: ControllerTiming(
                    cycle: cycle, frequency: 1, phase: 0, startTime: 0, stopTime: 1
                ),
                seconds: seconds
            )
        }
        #expect(count(0.25, .loop) == 0)
        #expect(count(0.75, .loop) == 1)
        // The jump back to the first key is a change too.
        #expect(count(1.25, .loop) == 2)
        #expect(count(1.75, .loop) == 3)
        #expect(count(5, .clamp) == 1)
        #expect(count(1.25, .reverse) == 1)
        #expect(count(1.75, .reverse) == 2)
    }

    @Test func aSequenceThatLeavesTheGenerationUnsetKeepsTheBolt() throws {
        var values = Self.parameters(subdivisions: 2)
        var begin = LightningTracks(timing: ControllerTiming(
            cycle: .clamp, frequency: 1, phase: 0, startTime: 0, stopTime: 1
        ))
        begin.generation = [NIFKey(time: 0, value: false), NIFKey(time: 0.5, value: true)]
        begin.length = [NIFKey(time: 0, value: 100), NIFKey(time: 1, value: 300)]
        values.sequenceTracks = ["mbegin": begin, "mloop": LightningTracks(timing: Self.loop)]
        let bolt = LightningBolt(parameters: values, seed: 2)
        var play = bolt.play(LightningBolt.Play(), switchedTo: "mBegin", at: 0)
        #expect(play.sequence == "mbegin")
        #expect(bolt.quads(at: 0.25, play: play).isEmpty)
        let shown = try #require(bolt.moment(at: 1, play: play))
        #expect(shown.isOn && shown.values.length == 300)
        play = bolt.play(play, switchedTo: "mLoop", at: 1)
        let held = try #require(bolt.moment(at: 3, play: play))
        #expect(held.isOn, "the loop keeps the bolt the begin sequence showed")
        #expect(held.values.length == 300)
        #expect(held.generation == shown.generation)
        #expect(bolt.play(play, switchedTo: "unknown", at: 4) == play)
    }

    @Test func theBufferHoldsTheMostQuadsTheFieldsCanGrow() {
        #expect(LightningBolt(parameters: Self.parameters(subdivisions: 4), seed: 1).maxQuads == 32)
        let branched = Self.parameters(subdivisions: 3, branches: 2)
        // 16 for the main bolt, and two children of 8 with one child of 4 each.
        #expect(LightningBolt(parameters: branched, seed: 1).maxQuads == 16 + 2 * (8 + 4))
        let deep = Self.parameters(subdivisions: 12, branches: 10)
        #expect(LightningBolt(parameters: deep, seed: 1).maxQuads == LightningBolt.quadCapacity)
    }

    @Test func aQuadPacksItsSideAndBothAlphasForTheRibbonShader() {
        let quad = LightningQuad(
            start: [0, 0, 0], end: [0, 10, 0], side: [1, 0, 0], width: 4,
            alpha: [0.25, 0.75], along: [0, 0.5]
        )
        var model = matrix_identity_float4x4
        model.columns.0.x = 2
        model.columns.3 = [5, 0, 0, 1]
        let instance = quad.instance(model: model)
        #expect(instance.positionSize == [5, 0, 0, 8])
        #expect(instance.rotation == [5, 10, 0, 8])
        #expect(instance.color == [1, 0, 0, 0.25])
        #expect(instance.uvRect == [0, 0.5, RibbonMode.fixedSide, 0.75])
    }
}
