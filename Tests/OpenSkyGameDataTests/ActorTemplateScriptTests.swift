@testable import FormatsTesting
import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
import Testing

struct ActorTemplateScriptTests {
    private static let useScript: UInt16 = 0x0200

    @Test("a base with the script flag takes its template's scripts")
    func theScriptFlagDelegates() throws {
        let resolver = try resolver(
            npc(0x10, script: "OwnScript", flags: Self.useScript, template: 0x20),
            npc(0x20, script: "TemplateScript")
        )
        let scripts = try resolver.resolveScripts(base: FormID(0x10))
        #expect(scripts.value.map(\.name) == ["TemplateScript"])
        #expect(scripts.source == FormID(0x20))
    }

    @Test("a base without the script flag keeps its own scripts")
    func aClearFlagKeepsOwnScripts() throws {
        let resolver = try resolver(
            npc(0x10, script: "OwnScript", template: 0x20),
            npc(0x20, script: "TemplateScript")
        )
        #expect(try resolver.resolveScripts(base: FormID(0x10)).value.map(\.name) == ["OwnScript"])
    }

    private func npc(
        _ formID: UInt32, script: String, flags: UInt16 = 0, template: UInt32? = nil
    ) throws -> ActorBase {
        let vmad = ESMFixture.field(
            "VMAD", VMADFixture.payload(scripts: [.init(script, properties: [])])
        )
        let bytes = FactionFixture.actor(
            formID: formID, editorID: "Actor\(formID)", templateFlags: flags,
            template: template, aiData: vmad
        )
        return try ActorBase(record: ESMFixture.parseRecord(bytes), localized: false)
    }

    private func resolver(_ npcs: ActorBase...) -> ActorTemplateResolver {
        ActorTemplateResolver(
            actors: Dictionary(uniqueKeysWithValues: npcs.map { ($0.formID.rawValue, $0) }),
            leveledActors: [:]
        )
    }
}
