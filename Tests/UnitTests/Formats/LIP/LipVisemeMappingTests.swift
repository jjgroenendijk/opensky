@testable import opensky
import Testing

@Suite("LIP slot to TRI target mapping")
struct LipVisemeMappingTests {
    @Test("the inferred speech table is complete, unique and stable")
    func table() {
        #expect(LipVisemeMapping.entries.count == 16)
        #expect(Set(LipVisemeMapping.entries.map(\.slot)).count == 16)
        #expect(Set(LipVisemeMapping.entries.map(\.target)).count == 16)
        #expect(LipVisemeMapping.entries.first == .init(slot: 0, target: "Aah"))
        #expect(LipVisemeMapping.entries.last == .init(slot: 30, target: "W"))
    }

    @Test("known slots map and unknown or unavailable slots are tallied")
    func mappingTally() {
        let sample = LIPSample(
            trackTime: 0.5,
            weightsBySlot: [0: 0.75, 1: 0.25, 2: 0.5, 32: 0.1]
        )
        let mapped = LipVisemeMapping.map(sample, availableTargets: ["Aah"])

        #expect(mapped.weights == ["Aah": 0.75])
        #expect(mapped.unmappedActiveSlots == [1, 2, 32])
    }
}
