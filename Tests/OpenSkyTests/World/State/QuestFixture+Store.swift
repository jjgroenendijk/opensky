import FormatsESMTesting
import Foundation
@testable import OpenSkyEngine
@testable import OpenSkyFormatsESM

extension QuestFixture {
    static func store(_ records: Data) throws -> QuestStore {
        try QuestStore(file: ESMFile(data: plugin(records)), pluginName: "Test.esm")
    }
}
