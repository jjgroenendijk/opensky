public import Foundation
@testable import OpenSkyFormatsESM
public import OpenSkyFormatsTesting
@testable public import OpenSkyGameData

extension QuestFixture {
    public static func store(
        _ records: Data,
        pluginName: String = "Test.esm"
    ) throws -> QuestStore {
        try QuestStore(file: ESMFile(data: plugin(records)), pluginName: pluginName)
    }
}
