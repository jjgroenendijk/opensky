// A settings store over one synthetic plugin, for the settings structs' tests.

import Foundation
import OpenSkyFormatsTesting
import OpenSkyGameData

extension GameSettingFixture {
    /// A store whose one plugin, `Tuning.esp`, defines `settings`.
    public static func store(_ settings: [String: GameSettingFixtureValue]) throws
        -> GameSettingStore
    {
        try GameSettingStore(plugins: [("Tuning.esp", plugin(settings: settings))])
    }
}
