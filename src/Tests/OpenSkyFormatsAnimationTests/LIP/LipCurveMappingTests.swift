@testable import OpenSkyFormatsAnimation
import OpenSkyTagsTesting
import Testing

@Suite("LIP slot to TRI target and head mapping", .tags(.parser))
struct LipCurveMappingTests {
    private static func sample(_ values: [Int: Float]) -> LIPSample {
        LIPSample(values: (0 ..< 33).map { values[$0] ?? 0 })
    }

    @Test("slots 0 to 29 name 30 distinct targets in vanilla spelling")
    func table() {
        #expect(LipCurveMapping.slotTargets.count == 30)
        #expect(Set(LipCurveMapping.slotTargets.values).count == 30)
        #expect(LipCurveMapping.slotTargets[0] == "Aah")
        #expect(LipCurveMapping.slotTargets[3] == "ChJSh")
        #expect(LipCurveMapping.slotTargets[15] == "W")
        #expect(LipCurveMapping.slotTargets[16] == "BlinkLeft")
        #expect(LipCurveMapping.slotTargets[29] == "SquintRight")
    }

    @Test("names match without case and keep the face's own spelling")
    func caseInsensitiveBinding() {
        let binding = LipCurveMapping.binding(
            slotsPerFrame: 33, availableTargets: ["BMp", "w", "i", "BlinkLeft"]
        )
        #expect(binding.morphTargets == [2: "BMp", 8: "i", 15: "w", 16: "BlinkLeft"])
    }

    @Test("weights clamp to 0...1, head angles keep their sign")
    func mapsWeightsAndHead() {
        let binding = LipCurveMapping.binding(
            slotsPerFrame: 33, availableTargets: ["Aah", "BrowUpLeft"]
        )
        let mapped = LipCurveMapping.map(
            Self.sample([0: 0.75, 22: 1.3, 1: 0.25, 20: 0.1, 30: 0.1, 31: -0.02, 32: -0.05]),
            binding: binding
        )

        #expect(mapped.weights == ["Aah": 0.75, "BrowUpLeft": 1])
        #expect(mapped.head == LipHeadMotion(pitch: 0.1, roll: -0.02, yaw: -0.05))
        #expect(mapped.unmappedActiveSlots == [1, 20])
    }

    @Test("a creature track binds nothing and moves no head")
    func creatureTrack() {
        let binding = LipCurveMapping.binding(slotsPerFrame: 8, availableTargets: ["Aah"])
        let mapped = LipCurveMapping.map(
            LIPSample(values: [0.5, 0, 0, 0, 0, 0, 0, 0.2]), binding: binding
        )

        #expect(mapped.weights.isEmpty)
        #expect(mapped.head == .zero)
        #expect(mapped.unmappedActiveSlots == [0, 7])
    }
}
