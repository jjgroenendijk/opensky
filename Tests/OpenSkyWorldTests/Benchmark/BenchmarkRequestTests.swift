// The benchmark request: presets, scene ids, setting text, and the app's launch arguments.

import OpenSkyGameData
@testable import OpenSkyWorld
import Testing

struct BenchmarkRequestTests {
    @Test func presetsGrowFromQuickToFull() {
        let quick = BenchmarkPreset.quick.scenes()
        let standard = BenchmarkPreset.standard.scenes()
        let full = BenchmarkPreset.full.scenes()
        #expect(quick.map(\.id) == BenchmarkTour.quickSceneIDs)
        #expect(quick.count < standard.count && standard.count < full.count)
        #expect(!standard.contains { $0.group == .dlc })
        #expect(full.count == BenchmarkTour.scenes.count)
    }

    @Test func sceneIdsReplaceThePresetAndAnUnknownIdFails() throws {
        let request = BenchmarkRequest(sceneIDs: ["dragonsreach", "whiterun"])
        #expect(try request.scenes().map(\.id) == ["dragonsreach", "whiterun"])
        #expect(throws: BenchmarkRequestError.unknownScene("atlantis")) {
            try BenchmarkRequest(sceneIDs: ["atlantis"]).scenes()
        }
        #expect(throws: BenchmarkRequestError.unknownScene("atlantis")) {
            try BenchmarkRequest(captureScene: "atlantis").scenes()
        }
    }

    @Test func settingTextTakesNumbersSwitchesAndChoices() throws {
        let off = try BenchmarkRequest.parseSetting("rendering.gpuCulling=off")
        #expect(off.id == "rendering.gpuCulling" && off.value == 0)
        #expect(try BenchmarkRequest.parseSetting("rendering.gpuCulling=on").value == 1)
        #expect(try BenchmarkRequest.parseSetting("rendering.renderScale=2").value == 2)
        #expect(throws: BenchmarkRequestError.unknownSetting("no.such")) {
            try BenchmarkRequest.parseSetting("no.such=1")
        }
        #expect(throws: BenchmarkRequestError.self) {
            try BenchmarkRequest.parseSetting("rendering.gpuCulling")
        }
        #expect(throws: BenchmarkRequestError.badSettingValue(
            id: "rendering.gpuCulling",
            value: "maybe"
        )) {
            try BenchmarkRequest.parseSetting("rendering.gpuCulling=maybe")
        }
    }

    @Test func overridesAreCheckedAgainstTheCatalog() throws {
        let overrides = try BenchmarkRequest(settings: ["rendering.gpuCulling": 0])
            .settingOverrides()
        #expect(overrides[.gpuCulling] == 0)
        #expect(throws: BenchmarkRequestError.unknownSetting("bogus")) {
            try BenchmarkRequest(settings: ["bogus": 1]).settingOverrides()
        }
    }

    @Test func theAppReadsAPresetFlagOrAJSONRequest() throws {
        #expect(try BenchmarkRequest.fromAppArguments(["OpenSky"]) == nil)
        let flag = try #require(try BenchmarkRequest.fromAppArguments([
            "OpenSky",
            "--benchmark",
            "quick"
        ]))
        #expect(flag.preset == .quick && flag.quitWhenDone)
        let bare = try #require(try BenchmarkRequest.fromAppArguments(["OpenSky", "--benchmark"]))
        #expect(bare.preset == .standard)
        let sent = BenchmarkRequest(
            preset: .full, sceneIDs: ["riften"], overlay: false, outDirectory: "/tmp/run",
            settings: ["rendering.renderScale": 1], quitWhenDone: true, loadPasses: false
        )
        let read = try BenchmarkRequest.fromAppArguments([
            "OpenSky",
            "--benchmark-request",
            sent.encodedJSON
        ])
        #expect(read == sent)
        #expect(throws: BenchmarkRequestError.self) {
            try BenchmarkRequest.fromAppArguments(["OpenSky", "--benchmark", "huge"])
        }
        #expect(throws: BenchmarkRequestError.self) {
            try BenchmarkRequest.fromAppArguments(["OpenSky", "--benchmark-request", "{"])
        }
    }
}
