// HAZD lookup with its spell, light, impact-data, and sound links resolved.
// A link to a record outside the index counts as dangling. See docs/formats/hazards.md.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM

nonisolated public struct HazardLinks: Equatable, Sendable {
    public let spell: RecordLink?
    public let light: RecordLink?
    public let impactDataSet: RecordLink?
    public let sound: RecordLink?
    public let imageSpaceModifier: RecordLink?

    public var all: [RecordLink] {
        [spell, light, impactDataSet, sound, imageSpaceModifier].compactMap(\.self)
    }
}

nonisolated public struct HazardStore: Sendable {
    public static let linkedTypes: Set<FourCC> = ["HAZD", "SPEL", "LIGH", "IPDS", "SNDR", "IMAD"]

    public let hazards: TypedRecordStore<Hazard>
    /// Links whose target the index does not hold.
    public let danglingLinkCount: Int

    /// Build `index` over `linkedTypes`, or links to the missing types count as dangling.
    public init(index: RecordIndex) {
        hazards = TypedRecordStore(
            index: index,
            types: ["HAZD"],
            decode: { try Hazard(record: $0.record, localized: $0.localized) },
            editorID: \.editorID
        )
        let store = hazards
        danglingLinkCount = hazards.records
            .flatMap { store.links(of: $0).all }
            .count(where: \.isDangling)
    }

    public init(plugins: [(name: String, file: ESMFile)]) {
        self.init(index: RecordIndex(plugins: plugins, recordTypes: Self.linkedTypes))
    }

    public func links(of hazard: ResolvedRecord<Hazard>) -> HazardLinks {
        hazards.links(of: hazard)
    }
}

nonisolated extension TypedRecordStore where Record == Hazard {
    func links(of hazard: ResolvedRecord<Hazard>) -> HazardLinks {
        let properties = hazard.record.properties
        return HazardLinks(
            spell: link(properties?.spell, from: hazard),
            light: link(properties?.light, from: hazard),
            impactDataSet: link(properties?.impactDataSet, from: hazard),
            sound: link(properties?.sound, from: hazard),
            imageSpaceModifier: link(hazard.record.imageSpaceModifier, from: hazard)
        )
    }
}
