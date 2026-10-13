// PackageProcedureCensus: the procedures package trees use, and which ones an actor
// runs, over synthetic PACK records.

import Foundation
import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyWorld
import Testing

struct PackageProcedureCensusTests {
    @Test func countsEachProcedureOfTheResolvedTree() throws {
        let template = try PackageRuntimeFixture.package(
            id: 0x200, editorID: "Guard", procedureNames: ["Travel", "Acquire"]
        )
        let concrete = try PackageRuntimeFixture.package(id: 0x100, template: 0x200)
        let broken = try PackageRuntimeFixture.package(id: 0x300, template: 0x999)
        let store = PackageStore(
            packages: [template, concrete, broken],
            actorTemplates: ActorTemplateResolver(actors: [:], leveledActors: [:])
        )
        let census = PackageProcedureCensus(store: store)

        #expect(census.packageCount == 3)
        #expect(census.procedures.uses == ["travel": 2, "acquire": 2])
        #expect(census.procedures.left(where: PackageProcedureCensus.isRunnable).map(\.name)
            == ["acquire"])
        #expect(census.failures.total == 1)
    }
}
