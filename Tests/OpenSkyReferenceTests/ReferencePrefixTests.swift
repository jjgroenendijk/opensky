// The prefix layout, its status, the launch plan, the settings, and the ini edit.

import CoreGraphics
import Foundation
@testable import OpenSkyReference
import Testing

struct ReferencePrefixTests {
    private let root = URL(filePath: "/Volumes/x/prefix", directoryHint: .isDirectory)

    @Test func layoutFollowsTheWindowsSteamFolders() {
        let prefix = ReferencePrefix(root: root)
        #expect(prefix.gameExecutable.path(percentEncoded: false) == "/Volumes/x/prefix/drive_c/"
            + "Program Files (x86)/Steam/steamapps/common/Skyrim Special Edition/SkyrimSE.exe")
        #expect(prefix.appManifest.lastPathComponent == "appmanifest_489830.acf")
        #expect(prefix.batchFile(named: "opensky").lastPathComponent == "opensky")
    }

    @Test func documentsBelongToTheFirstRealWineUser() {
        let prefix = ReferencePrefix(root: root)
        let documents = prefix.documentsDirectory(users: ["Public", "jj"])
        #expect(documents?.path(percentEncoded: false)
            == "/Volumes/x/prefix/drive_c/users/jj/Documents/My Games/Skyrim Special Edition/")
        #expect(prefix.documentsDirectory(users: ["Public"]) == nil)
    }

    @Test func statusNamesTheFirstMissingPiece() {
        let prefix = ReferencePrefix(root: root)
        #expect(ReferencePrefixStatus(prefix: nil) == .notSet)
        #expect(ReferencePrefixStatus(prefix: root) { _ in false } == .missing(root.path()))
        #expect(ReferencePrefixStatus(prefix: root) { $0 == prefix.driveC }
            == .noSteam(root.path()))
        let ready = ReferencePrefixStatus(prefix: root) { _ in true }
        #expect(ready.isReady)
    }

    @Test func launchRunsSteamThenTheGameInsideThePrefix() {
        let wine = URL(filePath: "/opt/wine64")
        let plan = ReferenceLaunchPlan(
            prefix: ReferencePrefix(root: root), wine: wine, baseEnvironment: ["HOME": "/h"],
            clientDownloaded: true
        )
        #expect(plan.steam.arguments == [
            #"C:\Program Files (x86)\Steam\steam.exe"#,
            "-no-cef-sandbox", "-cef-single-process", "-noverifyfiles"
        ])
        #expect(!ReferenceLaunchPlan.steamArguments(clientDownloaded: false)
            .contains("-noverifyfiles"))
        #expect(plan.game.arguments.last?.hasSuffix(#"\SkyrimSE.exe"#) == true)
        #expect(plan.game.workingDirectory == ReferencePrefix(root: root).gameDirectory)
        #expect(plan.environment["WINEPREFIX"] == "/Volumes/x/prefix/")
        #expect(plan.environment["MTL_HUD_ENABLED"] == "0")
        #expect(plan.environment["WINEDLLOVERRIDES"]?.hasPrefix("bcrypt=b;ncrypt=b;") == true)
        #expect(plan.environment["SteamAppId"] == nil)
        #expect(plan.gameEnvironment["SteamAppId"] == "489830")
        #expect(plan.gameEnvironment["SteamGameId"] == "489830")
        #expect(plan.gameEnvironment["GST_PLUGIN_SYSTEM_PATH"]
            == "/Volumes/x/prefix/opensky-runtime/gstreamer/lib/gstreamer-1.0")
        #expect(plan.environment["DYLD_FALLBACK_LIBRARY_PATH"] == nil)
        #expect(plan.environment["HOME"] == "/h")
    }

    @Test func environmentBeatsDefaultsAndWineFallsBackToThePrefixRuntime() throws {
        let defaults = try #require(UserDefaults(suiteName: "ReferencePrefixTests-\(UUID())"))
        defaults.set("/from/defaults", forKey: ReferenceSettings.prefixDefaultsKey)
        #expect(ReferenceSettings.prefix(environment: [:], userDefaults: defaults)?
            .path(percentEncoded: false) == "/from/defaults/")
        #expect(ReferenceSettings.prefix(
            environment: [ReferenceSettings.prefixEnvironmentKey: "/from/env"],
            userDefaults: defaults
        )?.path(percentEncoded: false) == "/from/env/")
        let bundled = ReferencePrefix(root: root).wine.path(percentEncoded: false)
        let wine = ReferenceSettings.wine(prefix: root, environment: [:], userDefaults: nil) {
            $0 == bundled
        }
        #expect(wine?
            .path(percentEncoded: false) == "/Volumes/x/prefix/opensky-runtime/wine/bin/wine")
        #expect(ReferenceSettings.wine(prefix: nil, environment: [:], userDefaults: nil) == nil)
    }

    @Test func prefsIniSetsTheDisplayKeysAndKeepsTheRest() {
        let text = "[Display]\r\nbFull Screen=1\r\niSize W=1920\r\nfGamma=1.0\r\n\r\n"
            + "[Audio]\r\nfVal=1\r\n"
        let frame = ReferenceWindowFrame(x: 0, y: 25, width: 1280, height: 720)
        let result = ReferencePrefsIni.apply(to: text, frame: frame)
        #expect(result == "[Display]\r\nbFull Screen=0\r\niSize W=1280\r\nfGamma=1.0\r\n"
            + "bBorderless=1\r\niSize H=720\r\n\r\n"
            + "[Audio]\r\nfVal=1\r\n")
    }

    @Test func prefsIniAddsAMissingSection() {
        let frame = ReferenceWindowFrame(x: 10, y: 20, width: 800, height: 600)
        let text = "[General]\nsA=b\nbAlwaysActive=1\n"
        let result = ReferencePrefsIni.apply(to: text, frame: frame)
        #expect(result == "[General]\r\nsA=b\r\n"
            + "[Display]\r\nbBorderless=1\r\nbFull Screen=0\r\niSize W=800\r\niSize H=600\r\n")
    }

    @Test func gameIniKeepsTheGameRunningBehindOtherApps() {
        #expect(ReferencePrefsIni.applyGameIni(to: "[General]\r\nsLanguage=ENGLISH\r\n")
            == "[General]\r\nsLanguage=ENGLISH\r\nbAlwaysActive=1\r\n")
    }

    @Test func presetSetsItsKeysAndKeepsTheOthers() {
        let preset = "; Low\r\n[Display]\r\niShadowMapResolution=1024\r\n[Grass]\r\nb=0\r\n"
        let text = "[Display]\r\niShadowMapResolution=4096\r\niSize W=1280\r\n"
            + "[Controls]\r\nfMouse=1\r\n"
        #expect(ReferencePrefsIni.apply(preset: preset, to: text)
            == "[Display]\r\niShadowMapResolution=1024\r\niSize W=1280\r\n"
            + "[Controls]\r\nfMouse=1\r\n[Grass]\r\nb=0\r\n")
    }

    @Test func sideBySideSplitsTheScreenIntoTwoEqualPictures() {
        let layout = ReferenceSideBySide(
            visible: CGRect(x: 0, y: 80, width: 1728, height: 1000),
            screenHeight: 1117, titleBar: 28
        )
        #expect(layout.openSkyContent == CGRect(x: 0, y: 566, width: 864, height: 486))
        #expect(layout.reference == ReferenceWindowFrame(x: 864, y: 65, width: 864, height: 486))
    }

    @Test func sideBySideFitsAShortScreenByHeight() {
        let layout = ReferenceSideBySide(
            visible: CGRect(x: 0, y: 0, width: 3000, height: 628), screenHeight: 628, titleBar: 28
        )
        #expect(layout.reference == ReferenceWindowFrame(x: 1500, y: 28, width: 1066, height: 600))
        #expect(layout.openSkyContent.maxX == 1500)
    }

    @Test func removingAKeyFromAMissingSectionChangesNothing() {
        let text = ReferenceIni.set(
            [ReferenceIniValue("sA", nil)],
            in: "General",
            of: "[D]\nfA=1\n"
        )
        #expect(text == "[D]\r\nfA=1\r\n")
        let removed = ReferenceIni.set(
            [ReferenceIniValue("sa", nil)], in: "general", of: "[General]\nsA=b\nsB=c\n"
        )
        #expect(removed == "[General]\r\nsB=c\r\n")
    }
}

struct ReferenceWindowTests {
    @Test func theBiggestWineWindowOnTheNormalLayerWins() {
        let windows = [
            ReferenceWindowInfo(
                id: 1,
                ownerName: "wine64-preloader",
                layer: 0,
                width: 400,
                height: 300
            ),
            ReferenceWindowInfo(
                id: 2,
                ownerName: "SkyrimSE.exe",
                layer: 0,
                width: 1280,
                height: 720
            ),
            ReferenceWindowInfo(
                id: 3,
                ownerName: "wine64-preloader",
                layer: 25,
                width: 3000,
                height: 2000
            ),
            ReferenceWindowInfo(id: 4, ownerName: "OpenSky", layer: 0, width: 1280, height: 720)
        ]
        #expect(ReferenceWindow.pick(windows)?.id == 2)
        #expect(ReferenceWindow.pick([windows[3]]) == nil)
        let small = ReferenceWindowFrame(x: 0, y: 0, width: 400, height: 300)
        #expect(ReferenceWindow.pick(windows, expected: small)?.id == 1)
    }

    @Test func aWindowIsPlacedOnlyAtItsFramesCornerAndSize() {
        let frame = ReferenceWindowFrame(x: 720, y: 62, width: 720, height: 405)
        let window = ReferenceWindowInfo(
            id: 1, ownerName: "wine", layer: 0, width: 720, height: 405, x: 720, y: 62
        )
        #expect(window.isPlaced(at: frame))
        var moved = window
        moved.x = 0
        #expect(!moved.isPlaced(at: frame))
        var resized = window
        resized.height = 720
        #expect(!resized.isPlaced(at: frame))
    }

    @Test func manifestSitsInSteamapps() {
        let install = URL(
            filePath: "/s/steamapps/common/Skyrim Special Edition",
            directoryHint: .isDirectory
        )
        #expect(ReferenceWindow.manifest(forInstall: install).path(percentEncoded: false)
            == "/s/steamapps/appmanifest_489830.acf")
    }
}
