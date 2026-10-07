// How long a scene line lasts: the length of each response's voice file, read off
// the main actor. A response with no voice file keeps the text estimate. The game
// waits for the voice file to end (<https://ck.uesp.net/wiki/Category:Scenes>).

import Foundation
import OpenSkyFormatsAudio
import OpenSkyFormatsESM
import OpenSkyGameData

@MainActor
public final class SceneVoiceTimer {
    private let locator: VoiceLineLocator
    private let loader: AssetLoader<String, Float>

    public init(locator: VoiceLineLocator, loader: AssetLoader<String, Float>) {
        self.locator = locator
        self.loader = loader
    }

    /// Reads each `.fuz` through `read` on the shared load queue.
    public convenience init(
        locator: VoiceLineLocator,
        read: @escaping @Sendable (String) throws -> Data
    ) {
        self.init(locator: locator, loader: AssetLoader { path in
            try Self.seconds(fuzData: read(path))
        })
    }

    /// Seconds for the whole line, or nil while a voice file loads. `texts` holds
    /// one resolved text per response, for the responses with no voice file.
    public func duration(of info: TopicInfo, voiceType: String?, texts: [String?]) -> Float? {
        guard let voiceType else { return SceneCore.lineDuration(texts: texts) }
        let lines = locator.lines(info: info, voiceType: voiceType)
        guard !lines.isEmpty, lines.count == texts.count else {
            return SceneCore.lineDuration(texts: texts)
        }
        var total: Float = 0
        var isLoading = false
        for (line, text) in zip(lines, texts) {
            switch loader.state(of: line.path) {
            case .loading: isLoading = true
            case let .ready(seconds): total += seconds
            case .failed: total += SceneCore.lineDuration(texts: [text])
            }
        }
        return isLoading ? nil : total
    }

    /// Moves finished reads in. Call once per frame.
    public func drain() {
        _ = loader.drain()
    }

    /// The xWMA packet table's playing time (docs/formats/fuz.md).
    nonisolated public static func seconds(fuzData: Data) throws -> Float {
        let audio = try FUZFile(data: fuzData).audio()
        guard let seconds = audio.declaredDuration else {
            throw FUZError.malformed("no dpds packet table to time the line by")
        }
        return Float(seconds)
    }
}
