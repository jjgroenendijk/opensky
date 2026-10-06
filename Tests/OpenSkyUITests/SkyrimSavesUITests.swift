// Library > Skyrim Saves against a folder of synthetic saves. The bundle links no fixture
// library, so it writes the header and picture only, which is all a listing reads.

import XCTest

final class SkyrimSavesUITests: OpenSkyUITestCase {
    /// `TESV_SAVEGAME`, the header (docs/formats/ess.md), then a 2x1 RGBA picture.
    private static func headerOnlySave(player: String) -> Data {
        var header = Data()
        func append32(_ value: UInt32) {
            withUnsafeBytes(of: value.littleEndian) { header.append(contentsOf: $0) }
        }
        func append16(_ value: UInt16) {
            withUnsafeBytes(of: value.littleEndian) { header.append(contentsOf: $0) }
        }
        func appendText(_ text: String) {
            append16(UInt16(text.utf8.count))
            header.append(contentsOf: Array(text.utf8))
        }
        append32(12)
        append32(1)
        appendText(player)
        append32(3)
        appendText("Helgen Keep")
        appendText("Sundas, 17th of Last Seed")
        appendText("NordRace")
        append16(0)
        append32(0)
        append32(0)
        header.append(Data(count: 8))
        append32(2)
        append32(1)
        append16(2)
        var file = Data("TESV_SAVEGAME".utf8)
        withUnsafeBytes(of: UInt32(header.count).littleEndian) { file.append(contentsOf: $0) }
        file.append(header)
        file.append(Data(repeating: 0x80, count: 8))
        return file
    }

    @MainActor
    func testSkyrimSavesListsAFolderOfSaves() throws {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "opensky-ess-uitest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        try Self.headerOnlySave(player: "Synthetic").write(to: folder.appending(path: "Save1.ess"))

        let launched = try launchApp(
            environment: ["OPENSKY_SKYRIM_SAVES": folder.path(percentEncoded: false)]
        )
        selectDestination("Destination-skyrimSaves", in: launched)
        let table = launched.tables["SkyrimSavesTable"]
        XCTAssertTrue(table.waitForExistence(timeout: 5))
        XCTAssertTrue(launched.staticTexts["SkyrimSavesFolderStatsLabel"].exists)
        XCTAssertTrue(launched.buttons["SkyrimSavesChooseControl"].exists)
        XCTAssertTrue(launched.buttons["SkyrimSavesReloadControl"].exists)
        XCTAssertTrue(launched.buttons["SkyrimSavesDryRunControl"].exists)
        XCTAssertTrue(table.staticTexts["Synthetic"].waitForExistence(timeout: 5))
        table.staticTexts["Synthetic"].click()
        let text = launched.textViews["SkyrimSavesInspectionText"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        XCTAssertFalse(launched.buttons["ScreenshotButton"].isEnabled)
    }
}
