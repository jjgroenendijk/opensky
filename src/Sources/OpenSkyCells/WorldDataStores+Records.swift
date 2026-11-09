public import OpenSkyCombatInterface
public import OpenSkyGameData

extension WorldDataStores: WorldRecordsPort {
    public var locationKeywords: KeywordStore? {
        locationStore?.keywords
    }

    public var leveledScriptEdits: LeveledScriptEdits? {
        actorValueBaselines?.leveling.scriptEdits
    }
}

extension WorldDataStores: CombatRecordsPort {}
