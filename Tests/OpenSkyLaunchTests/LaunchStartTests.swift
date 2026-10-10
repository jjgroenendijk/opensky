// Start options: parsing the saved value, validating the launcher's fields,
// and remembering the last choice.

import Foundation
import OpenSkyLaunch
import Testing

struct LaunchStartTests {
    private func isolatedDefaults() throws -> UserDefaults {
        let suite = "LaunchStartTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func storedValuesRoundTrip() {
        let starts: [LaunchStart] = [
            .normal, .cell("WhiterunBanneredMare"), .exterior(worldspace: "Tamriel", x: 6, y: -2)
        ]
        for start in starts {
            #expect(LaunchStart(storedValue: start.storedValue) == start)
        }
        #expect(LaunchStart.exterior(worldspace: "Tamriel", x: 6, y: -2).storedValue
            == "exterior:Tamriel:6:-2")
    }

    @Test func unreadableStoredValuesAreNil() {
        for text in [
            "",
            "cell:",
            "cell:Bad Name",
            "exterior:Tamriel:6",
            "exterior:Sovngarde:1:1",
            "exterior:Tamriel:x:1",
            "teleport:somewhere"
        ] {
            #expect(LaunchStart(storedValue: text) == nil, "\(text)")
        }
    }

    @Test func aCellNeedsAnEditorID() {
        #expect(LaunchStartForm(kind: .cell, cell: "  ").validate() == .failure(.emptyCell))
        #expect(LaunchStartForm(kind: .cell, cell: "Whiterun Inn").validate()
            == .failure(.badCellName))
        #expect(LaunchStartForm(kind: .cell, cell: " QASmoke ").validate()
            == .success(.cell("QASmoke")))
    }

    @Test func anExteriorNeedsAStreamedWorldspaceAndWholeCoordinates() {
        let form = LaunchStartForm(kind: .exterior, worldspace: "tamriel", x: "6", y: "-2")
        #expect(form.validate() == .success(.exterior(worldspace: "Tamriel", x: 6, y: -2)))
        var other = form
        other.worldspace = "Sovngarde"
        #expect(other.validate() == .failure(.worldspaceNotStreamed("Sovngarde")))
        var badX = form
        badX.x = "6.5"
        #expect(badX.validate() == .failure(.badCoordinate("X")))
        var farY = form
        farY.y = "500"
        #expect(farY.validate() == .failure(.badCoordinate("Y")))
    }

    @Test func everyProblemHasAReason() {
        let problems: [LaunchStartProblem] = [
            .emptyCell, .badCellName, .worldspaceNotStreamed(""), .badCoordinate("X")
        ]
        for problem in problems {
            #expect(!problem.reason.isEmpty)
        }
        #expect(LaunchStartProblem.badCoordinate("X").reason
            == "X must be a whole number from -64 to 64")
    }

    @Test func theFormRebuildsFromAStart() {
        let start = LaunchStart.exterior(worldspace: "Tamriel", x: -3, y: 9)
        #expect(LaunchStartForm(start).validate() == .success(start))
        #expect(LaunchStartForm(.cell("A")).kind == .cell)
    }

    @Test func theLastChoiceIsRemembered() throws {
        let defaults = try isolatedDefaults()
        #expect(LaunchPreferences.savedStart(userDefaults: defaults) == .normal)
        LaunchPreferences.remember(.cell("QASmoke"), userDefaults: defaults)
        #expect(LaunchPreferences.savedStart(userDefaults: defaults) == .cell("QASmoke"))
        defaults.set("garbage", forKey: LaunchPreferences.startKey)
        #expect(LaunchPreferences.savedStart(userDefaults: defaults) == .normal)
    }
}
