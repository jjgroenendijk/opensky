// The bridge plugin's state file, the command batches OpenSky writes, and the launch
// through SKSE's loader.

import Foundation
@testable import OpenSkyReference
import Testing

struct ReferenceBridgeTests {
    /// `state.json` as the plugin writes it in an exterior cell.
    private let exterior = """
    {"version":1,"batch":"0001","mainMenu":false,"loading":false,\
    "position":[1000.5,-2000.25,300],"pitchDegrees":10,"headingDegrees":0,\
    "cellFormID":3456,"cell":"","interior":false,"grid":[4,-8],\
    "worldspace":"Tamriel","worldspaceFormID":60,"hour":13.5,"weatherFormID":1106412,\
    "worldFOV":80.69,"firstPersonFOV":90,"firstPerson":true}
    """

    private func decode(_ text: String) throws -> ReferenceBridgeState {
        try JSONDecoder().decode(ReferenceBridgeState.self, from: Data(text.utf8))
    }

    private func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appending(
                path: "ReferenceBridgeTests-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    @Test func exteriorStateBecomesOpenSkysView() throws {
        let state = try decode(exterior)
        let view = try #require(state.view)
        #expect(view.feet == [1000.5, -2000.25, 300])
        #expect(view.yawDegrees == 90)
        #expect(view.pitchDegrees == -10)
        #expect(abs(view.fovYDegrees - 65) < 0.01)
        #expect(view.place == .exterior(worldspace: "Tamriel", grid: SIMD2(4, -8)))
        #expect(view.interiorFormID == nil)
        #expect(view.weatherFormID == 0x0010_E1EC)
        #expect(state.inWorld)
        #expect(state.isAt(.exterior(worldspace: "tamriel", grid: SIMD2(4, -8))))
        #expect(!state.isAt(.exterior(worldspace: "Tamriel", grid: SIMD2(4, -7))))
    }

    @Test func headingAndYawRoundTrip() {
        for yaw: Float in [-170, -90, 0, 45, 90, 180] {
            let view = ReferenceView(
                feet: .zero, yawDegrees: yaw, pitchDegrees: 0, fovYDegrees: 65, gameHour: 0,
                place: .interior(editorID: "A"), weatherFormID: nil, firstPerson: true
            )
            #expect(abs(ReferenceView.yaw(fromHeading: view.skyrimHeadingDegrees) - yaw) < 0.001)
        }
    }

    @Test func interiorKeepsTheCellFormIDForOpenSky() throws {
        let state = try decode("""
        {"version":1,"batch":"","mainMenu":false,"loading":false,"position":[1,2,3],\
        "pitchDegrees":0,"headingDegrees":90,"cellFormID":93147,"cell":"WhiterunBanneredMare",\
        "interior":true,"hour":8}
        """)
        let view = try #require(state.view)
        #expect(view.place == .interior(editorID: "WhiterunBanneredMare"))
        #expect(view.interiorFormID == 93147)
        #expect(view.yawDegrees == 0)
        #expect(view.fovYDegrees == ReferenceView.defaultFOVYDegrees)
        #expect(state.isAt(.interior(editorID: "whiterunbanneredmare")))
    }

    @Test func mainMenuHasNoView() throws {
        let state = try decode(#"{"version":1,"batch":"","mainMenu":true,"loading":false}"#)
        #expect(state.view == nil)
        #expect(!state.inWorld)
    }

    @Test func standingNearTheFeetIgnoresHeight() throws {
        let state = try decode(exterior)
        #expect(state.stands(at: SIMD3(1010, -2000, 0)))
        #expect(!state.stands(at: SIMD3(1100, -2000, 300)))
    }

    @Test func anOpenMessageBoxNamesItsButtons() throws {
        let state = try decode("""
        {"version":1,"batch":"","mainMenu":false,"loading":false,\
        "dialog":{"text":"Enable Survival Mode?","buttons":["Yes","No"]}}
        """)
        let dialog = try #require(state.dialog)
        #expect(dialog.buttons == ["Yes", "No"])
        #expect(dialog.buttonIndex(of: "no") == 1)
        #expect(dialog.buttonIndex(of: " Yes ") == 0)
        #expect(dialog.buttonIndex(of: "1") == 1)
        #expect(dialog.buttonIndex(of: "2") == nil)
        #expect(dialog.buttonIndex(of: "Maybe") == nil)
    }

    @Test func playingScenesNameTheirPhaseAndActors() throws {
        let state = try decode("""
        {"version":1,"batch":"","mainMenu":false,"loading":false,"scenes":[\
        {"formID":661852,"phase":-1,"actors":[\
        {"alias":29,"referenceFormID":656849,"loaded":false,"disabled":false,"dead":false}]}]}
        """)
        let scene = try #require(state.scenes?.first)
        #expect(scene.formID == 0xA195C)
        #expect(scene.phase == -1)
        #expect(scene.actors.map(\.alias) == [29])
        #expect(scene.actors.first?.loaded == false)
    }

    @Test func sendWritesOneWholeBatchWithWindowsLineEnds() throws {
        let bridge = try ReferenceBridge(folder: temporaryFolder())
        let name = try bridge.send(["fov 80", "set gamehour to 12"])
        let files = try FileManager.default
            .contentsOfDirectory(atPath: bridge.commandsFolder.path())
        #expect(files == ["\(name).txt"])
        let text = try String(
            contentsOf: bridge.commandsFolder.appending(path: "\(name).txt"), encoding: .utf8
        )
        #expect(text == "fov 80\r\nset gamehour to 12\r\n")
    }

    @Test func laterBatchesSortAfterEarlierOnes() {
        let first = ReferenceBridge.batchName(at: Date(timeIntervalSince1970: 9))
        let second = ReferenceBridge.batchName(at: Date(timeIntervalSince1970: 10))
        #expect(first < second)
    }

    @Test func aStaleStateMeansNoGameRuns() throws {
        let bridge = try ReferenceBridge(folder: temporaryFolder())
        try Data(exterior.utf8).write(to: bridge.stateFile)
        let written = Date()
        #expect(bridge.state(now: written) != nil)
        #expect(bridge.state(now: written.addingTimeInterval(60)) == nil)
        bridge.reset()
        #expect(bridge.state(now: written) == nil)
    }

    @Test func missingPartsAreNamedInInstallOrder() {
        #expect(ReferenceBridgePart.missing(names: [], hasLoader: false)
            == [.scriptExtender, .addressLibrary, .plugin])
        let installed: Set = ["versionlib-1-7-104-0.bin", "openskybridge.dll"]
        #expect(ReferenceBridgePart.missing(names: installed, hasLoader: true).isEmpty)
    }

    @Test func theLoaderStartsTheGameWhenSKSEIsInstalled() {
        let prefix = ReferencePrefix(root: URL(filePath: "/p", directoryHint: .isDirectory))
        let wine = URL(filePath: "/p/wine")
        let plain = ReferenceLaunchPlan(
            prefix: prefix, wine: wine, baseEnvironment: [:], clientDownloaded: true
        )
        let extended = ReferenceLaunchPlan(
            prefix: prefix, wine: wine, baseEnvironment: [:], clientDownloaded: true,
            scriptExtender: true
        )
        #expect(plain.game.arguments.first?.hasSuffix(#"\SkyrimSE.exe"#) == true)
        #expect(extended.game.arguments.first?.hasSuffix(#"\skse64_loader.exe"#) == true)
        #expect(extended.gameEnvironment["SteamAppId"] == ReferencePrefix.appID)
    }
}
