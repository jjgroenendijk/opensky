// An NPC with the Use Keywords template flag carries its template's keywords.
// Rules: docs/formats/actors.md.

import Foundation
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
import Testing

struct ActorKeywordTemplateTests {
    private static func keywords(_ ids: [UInt32]) -> Data {
        var list = Data()
        for id in ids {
            list.appendUInt32(id)
        }
        var count = Data()
        count.appendUInt32(UInt32(ids.count))
        return ESMFixture.field("KWSZ", count) + ESMFixture.field("KWDA", list)
    }

    private static func actor(
        _ formID: UInt32, flags: UInt16 = 0, template: UInt32? = nil, keywords: [UInt32]
    ) throws -> ActorBase {
        try ActorBase(record: FactionFixture.decode(FactionFixture.actor(
            formID: formID, editorID: "Actor\(formID)", templateFlags: flags,
            template: template, aiData: Self.keywords(keywords)
        )), localized: false)
    }

    @Test func theUseKeywordsFlagTakesTheTemplatesKeywords() throws {
        let template = try Self.actor(0x600, keywords: [0x900])
        let inheriting = try Self.actor(0x601, flags: 0x1000, template: 0x600, keywords: [0x901])
        let own = try Self.actor(0x602, template: 0x600, keywords: [0x902])
        let resolver = ActorValueResolver(
            templates: ActorTemplateResolver(
                actors: Dictionary(uniqueKeysWithValues: [template, inheriting, own].map {
                    ($0.formID.rawValue, $0)
                }),
                leveledActors: [:]
            ),
            races: [:]
        )
        #expect(ActorValueBaselineResolver
            .keywords(base: FormID(0x601), resolver: resolver) == [FormID(0x900)])
        #expect(ActorValueBaselineResolver
            .keywords(base: FormID(0x602), resolver: resolver) == [FormID(0x902)])
        #expect(ActorValueBaselineResolver
            .keywords(base: FormID(0x600), resolver: resolver) == [FormID(0x900)])
    }
}
