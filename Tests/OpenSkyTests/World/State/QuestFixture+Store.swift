import FormatsESMTesting
import Foundation
@testable import OpenSkyEngine
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData

extension QuestFixture {
    static func store(_ records: Data) throws -> QuestStore {
        try QuestStore(file: ESMFile(data: plugin(records)), pluginName: "Test.esm")
    }
}
