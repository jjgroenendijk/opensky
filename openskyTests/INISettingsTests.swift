import Foundation
@testable import opensky
import Testing

struct INISettingsTests {
    @Test func parsesSectionsCaseInsensitivelyAndLastAssignmentWins() {
        let file = INIFile(data: Data("""
        ; comment
        [TerrainManager]
        fBlockLevel0Distance = 20000
        FBLOCKLEVEL0DISTANCE=35000
        [Archive]
        sResourceArchiveList=One.bsa, Two.bsa
        """.utf8))

        #expect(file.string(section: "terrainmanager", key: "fblocklevel0distance") == "35000")
        #expect(
            file.string(section: "ARCHIVE", key: "sResourceArchiveList")
                == "One.bsa, Two.bsa"
        )
    }

    @Test func malformedHighPriorityFloatFallsThroughToValidSource() {
        let settings = INISettings(sources: [
            INISettingsSource(
                name: "default",
                file: INIFile(data: Data("[TerrainManager]\nvalue=42".utf8))
            ),
            INISettingsSource(
                name: "override",
                file: INIFile(data: Data("[TerrainManager]\nvalue=not-a-number".utf8))
            )
        ])

        let resolved = settings.float(section: "TerrainManager", key: "value")
        #expect(resolved?.value == 42)
        #expect(resolved?.source == "default")
    }

    @Test func terrainSettingsMergeSourcesAndRejectInvalidOrdering() {
        let valid = INISettings(sources: [INISettingsSource(
            name: "prefs",
            file: INIFile(data: Data("""
            [TerrainManager]
            fBlockLevel0Distance=12000
            fBlockLevel1Distance=24000
            fBlockMaximumDistance=96000
            fTreeLoadDistance=48000
            """.utf8))
        )])
        let snapshot = TerrainLODSettings.resolve(valid)
        #expect(snapshot.configuration == TerrainLODConfiguration(
            level0Distance: 12000,
            level1Distance: 24000,
            maximumDistance: 96000,
            treeLoadDistance: 48000
        ))
        #expect(snapshot.source == "prefs")

        let invalid = INISettings(sources: [INISettingsSource(
            name: "bad",
            file: INIFile(data: Data("""
            [TerrainManager]
            fBlockLevel0Distance=70000
            fBlockLevel1Distance=35000
            """.utf8))
        )])
        #expect(TerrainLODSettings.resolve(invalid).configuration == .fallback)
    }

    @Test func sidebarOverridePersistsOnlyCompleteValidConfiguration() throws {
        let suite = "TerrainLODSettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let configuration = TerrainLODConfiguration(
            level0Distance: 16384,
            level1Distance: 32768,
            maximumDistance: 131_072,
            treeLoadDistance: 65536
        )

        TerrainLODSettings.store(configuration, to: defaults)
        let loaded = TerrainLODSettings.load(root: nil, defaults: defaults)
        #expect(loaded.configuration == configuration)
        #expect(loaded.source == "OpenSky sidebar override")

        TerrainLODSettings.clearOverride(from: defaults)
        #expect(TerrainLODSettings.load(root: nil, defaults: defaults).configuration == .fallback)
    }
}
