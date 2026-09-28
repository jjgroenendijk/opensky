import FormatsTestSupport
import Foundation
@testable import OpenSky
@testable import OpenSkyFormats

extension QuestFixture {
    static func store(_ records: Data) throws -> QuestStore {
        try QuestStore(file: ESMFile(data: plugin(records)), pluginName: "Test.esm")
    }
}
