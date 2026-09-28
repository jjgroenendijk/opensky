// Positional `.lip` speech slots to the named TRI targets observed on Skyrim
// head expression containers. The file does not store these names. Even-slot
// ordering is a structural inference from the 33-slot grid (16 speech targets,
// two slots each, plus one trailing slot), and remains labelled uncertain in
// docs/formats/lip.md until a visual calibration establishes it.

import Foundation

nonisolated struct LipVisemeMappingEntry: Equatable {
    let slot: Int
    let target: String
}

nonisolated struct LipMappedSample: Equatable {
    let weights: [String: Float]
    let unmappedActiveSlots: [Int]
}

nonisolated enum LipVisemeMapping {
    static let entries: [LipVisemeMappingEntry] = [
        .init(slot: 0, target: "Aah"),
        .init(slot: 2, target: "BigAah"),
        .init(slot: 4, target: "BMP"),
        .init(slot: 6, target: "ChjSh"),
        .init(slot: 8, target: "DST"),
        .init(slot: 10, target: "Eee"),
        .init(slot: 12, target: "Eh"),
        .init(slot: 14, target: "FV"),
        .init(slot: 16, target: "i"),
        .init(slot: 18, target: "k"),
        .init(slot: 20, target: "N"),
        .init(slot: 22, target: "Oh"),
        .init(slot: 24, target: "OohQ"),
        .init(slot: 26, target: "R"),
        .init(slot: 28, target: "Th"),
        .init(slot: 30, target: "W")
    ]

    static let mappedSlots = Set(entries.map(\.slot))

    static func map(_ sample: LIPSample, availableTargets: Set<String>) -> LipMappedSample {
        var weights: [String: Float] = [:]
        var consumedSlots = Set<Int>()
        for entry in entries where availableTargets.contains(entry.target) {
            weights[entry.target] = sample.weightsBySlot[entry.slot] ?? 0
            consumedSlots.insert(entry.slot)
        }
        let active = sample.weightsBySlot
            .filter { $0.value > 0 && !consumedSlots.contains($0.key) }
            .map(\.key)
            .sorted()
        return LipMappedSample(weights: weights, unmappedActiveSlots: active)
    }
}
