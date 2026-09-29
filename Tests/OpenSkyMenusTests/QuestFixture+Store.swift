// A copy of Tests/OpenSkyQuestsTests/QuestFixture+Store.swift: each package test target
// that builds a quest store needs its own.

import FormatsESMTesting
import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData

extension QuestFixture {
    static func store(_ records: Data) throws -> QuestStore {
        try QuestStore(file: ESMFile(data: plugin(records)), pluginName: "Test.esm")
    }
}
