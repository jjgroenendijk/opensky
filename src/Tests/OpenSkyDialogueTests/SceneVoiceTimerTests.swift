// Scene line length from synthetic `.fuz` files: the line waits while a file
// loads, then lasts the packet table's playing time.

import Foundation
@testable import OpenSkyDialogue
import OpenSkyEngineTesting
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
import OpenSkyGameData
import Testing

@MainActor
struct SceneVoiceTimerTests {
    /// Two packets of 40,960 decoded bytes, two channels of 16 bits, at 44.1 kHz.
    private static let fileSeconds = Float(2 * 40960 / 4) / 44100

    /// One topic with one info of two responses.
    private func store() throws -> DialogueStore {
        try DialogueFixture.store(dialogueChildren: DialogueFixture.topicRecord(
            formID: 0x100, fields: DialogueFixture.editorID("VoicedTopic")
        ) + DialogueFixture.topicChildren(
            parent: 0x100,
            infos: DialogueFixture.infoRecord(
                formID: 0x200,
                fields: DialogueFixture.infoData()
                    + DialogueFixture.response(number: 1)
                    + DialogueFixture.response(number: 2)
            )
        ))
    }

    private func timer(
        load: @escaping @Sendable (String) throws -> Data
    ) throws -> SceneVoiceTimer {
        let locator = try VoiceLineLocator(dialogue: store(), quests: nil)
        let worker = ImmediateAssetLoadWorker<String, Float> { path in
            try SceneVoiceTimer.seconds(fuzData: load(path))
        }
        return SceneVoiceTimer(locator: locator, loader: AssetLoader(worker: worker))
    }

    private func info() throws -> TopicInfo {
        let info = try #require(store().info(FormID(0x200)))
        #expect(info.responses.count == 2)
        return info
    }

    @Test func aLineLastsItsVoiceFileOnceLoaded() throws {
        let fuz = FUZFixture.file(audio: XWMFixture.file(packetCount: 2))
        let timer = try timer { _ in fuz }
        let info = try info()
        let texts: [String?] = info.responses.map { _ in "Hi" }
        #expect(timer.duration(of: info, voiceType: "MaleNord", texts: texts) == nil)
        timer.drain()
        let seconds = try #require(timer.duration(of: info, voiceType: "MaleNord", texts: texts))
        #expect(abs(seconds - Self.fileSeconds * Float(texts.count)) < 0.0001)
    }

    /// No voice type, or no file for a response, keeps the text estimate.
    @Test func aLineWithoutAVoiceFileKeepsTheTextEstimate() throws {
        let timer = try timer { path in throw VFSError.fileNotFound(path: path) }
        let info = try info()
        let texts: [String?] = info.responses.map { _ in "Hi" }
        let estimate = SceneCore.lineDuration(texts: texts)
        #expect(timer.duration(of: info, voiceType: nil, texts: texts) == estimate)
        _ = timer.duration(of: info, voiceType: "MaleNord", texts: texts)
        timer.drain()
        #expect(timer.duration(of: info, voiceType: "MaleNord", texts: texts) == estimate)
    }
}
