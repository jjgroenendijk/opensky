@testable import opensky
import simd
import Testing

@Suite("FaceGen expression composition")
struct FaceMorphTests {
    @Test("weights compose position and normal deltas with clamping")
    func clampedComposition() {
        let target = FaceMorphTarget(name: "Aah", deltas: [
            MorphVertexDelta(position: SIMD3(2, 0, 0), normal: SIMD3(0, 1, 0)),
            MorphVertexDelta(position: SIMD3(0, 4, 0), normal: SIMD3(0, 0, 2))
        ])

        let high = FaceMorphComposer.compose(
            targets: [target], weights: ["Aah": 2], vertexCount: 2
        )
        let low = FaceMorphComposer.compose(
            targets: [target], weights: ["Aah": -1], vertexCount: 2
        )

        #expect(high[0].position == SIMD3(2, 0, 0))
        #expect(high[1].normal == SIMD3(0, 0, 2))
        #expect(low.allSatisfy { $0.position == .zero && $0.normal == .zero })
    }

    @Test("multiple named targets add and unknown weights do nothing")
    func additiveComposition() {
        let first = FaceMorphTarget(name: "Aah", deltas: [
            MorphVertexDelta(position: SIMD3(2, 0, 0), normal: SIMD3(0, 2, 0))
        ])
        let second = FaceMorphTarget(name: "BigAah", deltas: [
            MorphVertexDelta(position: SIMD3(0, 4, 0), normal: SIMD3(0, 0, 4))
        ])
        let result = FaceMorphComposer.compose(
            targets: [first, second],
            weights: ["Aah": 0.5, "BigAah": 0.25, "Unknown": 1],
            vertexCount: 1
        )

        #expect(result[0].position == SIMD3(1, 1, 0))
        #expect(result[0].normal == SIMD3(0, 1, 1))
    }

    @Test("triangle topology derives a normal delta")
    func normalDelta() throws {
        let tri = TRIFile(
            baseVertices: [SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0)],
            triangles: [TRITriangle(vertices: SIMD3(0, 1, 2))],
            morphTargets: [TRIMorphTarget(
                name: "Tilt",
                scale: 1,
                deltas: [SIMD3(0, 0, 0), SIMD3(0, 0, 1), SIMD3(0, 0, 0)]
            )]
        )
        let target = try #require(FaceMorphComposer.targets(from: tri).first)

        #expect(target.deltas[0].normal != .zero)
        #expect(target.deltas.count == tri.baseVertices.count)
    }

    @Test("unknown playback target increments the inspection tally")
    func unknownTargetTally() {
        let playback = FaceMorphPlayback(
            actor: FormID(0x1234),
            bindings: [:],
            pairedPaths: [],
            misses: [],
            worldBounds: nil
        )

        #expect(!playback.setWeight(1, for: "Missing"))
        #expect(playback.unknownTargetCount == 1)
    }

    @Test("morph vertex layout stays SIMD aligned")
    func layout() {
        #expect(MorphVertexLayout.positionOffset == 0)
        #expect(MorphVertexLayout.normalOffset == 16)
        #expect(MorphVertexLayout.stride == 32)
    }
}
