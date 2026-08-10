// Env-gated `.fuz` sweep over the user's read-only vanilla install: frame
// every voice file the archives hold, re-derive every voice file name from the
// records and measure it against the archive listing, then take one known line
// end to end — resolve its path from an INFO, decode it, play it under manual
// rendering, and watch the playback clock advance to the decoded duration.
//
// No game-derived bytes leave the run: the report is counts and derived names
// only, and it goes to gitignored `logs/`.
//
// Run: make realtest T='VoiceRealDataTests/framesEveryVoiceFile()'

import AVFAudio
import Foundation
@testable import opensky
import simd
import Testing

struct VoiceRealDataTests {
    private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    private static let pluginNames = [
        "Skyrim.esm", "Update.esm", "Dawnguard.esm", "HearthFires.esm", "Dragonborn.esm"
    ]

    /// Vanilla Skyrim SE, measured 2026-08-10. A drift here means the install
    /// changed or the parser did; either way the number is worth failing on.
    private static let expectedEntryCount = 75408

    @Test(.enabled(if: Self.dataRoot != nil))
    func framesEveryVoiceFile() throws {
        let root = try #require(Self.dataRoot)
        let vfs = VirtualFileSystem(root: root)
        let paths = vfs.archiveEntries().map(\.path).filter { $0.hasSuffix(".fuz") }
        #expect(paths.count == Self.expectedEntryCount, "voice entry count drift")

        var framed = 0
        var withLip = 0
        var monoCount = 0
        var declaredSeconds = 0.0
        var failures: [String] = []
        var sampleRates: [Int: Int] = [:]
        var versions: [UInt32: Int] = [:]
        for path in paths {
            do {
                // One file's bytes at a time: framed, counted, released. The
                // corpus is 75,408 files and the run is under an RSS watchdog.
                let file = try FUZFile(data: vfs.contents(forPath: path))
                framed += 1
                versions[file.version, default: 0] += 1
                if file.lipByteCount > 0 {
                    withLip += 1
                }
                let audio = try file.audio()
                sampleRates[audio.codec.sampleRate, default: 0] += 1
                if audio.codec.channelCount == 1 {
                    monoCount += 1
                }
                declaredSeconds += audio.declaredDuration ?? 0
            } catch {
                failures.append("\(path): \(String(describing: error))")
            }
        }
        #expect(failures.isEmpty, "voice files that did not frame: \(failures.prefix(5))")
        #expect(framed == paths.count)
        #expect(versions == [1: paths.count], "unexpected FUZE container version")
        // Voice is overwhelmingly mono, which is what the positional path wants
        // — but 539 vanilla lines are stereo, so the streamer's downmix is on
        // the voice path for real and not only in theory.
        #expect(monoCount > framed - 1000, "\(framed - monoCount) voice files are not mono")
        #expect(monoCount < framed, "the stereo voice lines vanished; downmix now untested")

        let report = """
        [INFO] voice framing: \(paths.count) entries, \(framed) framed, \(failures.count) failed
        [INFO] voice lip: \(withLip) with a lip blob, \(framed - withLip) without
        [INFO] voice audio: \(monoCount) mono, rates \
        \(sampleRates.sorted { $0.key < $1.key }.map { "\($0.key)x\($0.value)" }
            .joined(separator: " ")), \
        \(String(format: "%.1f", declaredSeconds / 3600)) hours declared
        """
        print(report)
        try Self.writeReport(report, named: "framing")
    }

    @Test(.enabled(if: Self.dataRoot != nil))
    func derivesVoiceFileNamesFromRecords() throws {
        let root = try #require(Self.dataRoot)
        let vfs = VirtualFileSystem(root: root)
        let paths = vfs.archiveEntries().map(\.path).filter { $0.hasSuffix(".fuz") }

        var dialogueStores: [(name: String, store: DialogueStore)] = []
        var questStores: [String: QuestStore] = [:]
        for pluginName in Self.pluginNames {
            let file = try ESMFile(url: root.dataURL.appending(path: pluginName))
            questStores[pluginName.lowercased()] = QuestStore(file: file, pluginName: pluginName)
            let dialogue = DialogueStore(file: file, pluginName: pluginName)
            if dialogue.infoCount > 0 {
                dialogueStores.append((pluginName, dialogue))
            }
        }

        var lines: [String] = []
        var totalActual = 0
        var totalMatched = 0
        var totalSpelledDifferently = 0
        for (pluginName, dialogue) in dialogueStores {
            let locator = VoiceLineLocator(dialogue: dialogue, questStores: questStores)
            var derived: Set<String> = []
            for topic in dialogue.sortedTopics() {
                for info in dialogue.infos(for: topic.formID) {
                    derived.formUnion(locator.fileNames(info: info).map(\.name))
                }
            }
            let prefix = "sound\\voice\\\(pluginName.lowercased())\\"
            let actual = Set(
                paths.filter { $0.hasPrefix(prefix) }
                    .compactMap { $0.split(separator: "\\").last.map(String.init) }
            )
            let missing = actual.subtracting(derived)
            // A name the records do not carry a response for at all cannot be
            // reached by any naming rule: it is a recording whose INFO was cut
            // or renumbered after the audio was exported.
            let spelledDifferently = missing.filter { name in
                derived.contains { Self.tail(of: $0) == Self.tail(of: name) }
            }
            totalActual += actual.count
            totalMatched += actual.count - missing.count
            totalSpelledDifferently += spelledDifferently.count
            lines.append(
                "[INFO] \(pluginName): \(actual.count) archive names, \(derived.count) derived, "
                    + "\(actual.count - missing.count) explained, "
                    + "\(spelledDifferently.count) spelled differently, "
                    + "\(missing.count - spelledDifferently.count) naming no INFO response"
            )
        }
        let explained = Double(totalMatched) / Double(totalActual)
        // Measured 2026-08-10: 43,753 of 44,325 names, with 86 spelled
        // differently (editor IDs renamed after the audio was exported) and
        // 486 naming responses the records no longer carry. The gate is a
        // floor, not the exact number, so a mod-free reinstall drift does not
        // fail the suite while a broken rule still does.
        #expect(explained > 0.98, "voice name derivation fell to \(explained)")
        #expect(
            totalSpelledDifferently < 200,
            "\(totalSpelledDifferently) names the rule spells differently"
        )
        let report = (lines + [
            "[INFO] TOTAL: \(totalMatched) of \(totalActual) explained "
                + String(format: "(%.3f%%)", explained * 100)
                + ", \(totalSpelledDifferently) spelled differently"
        ]).joined(separator: "\n")
        print(report)
        try Self.writeReport(report, named: "names")
    }

    @Test(.enabled(if: Self.dataRoot != nil))
    func playsOneResolvedLineAndAdvancesTheClock() async throws {
        let root = try #require(Self.dataRoot)
        let vfs = VirtualFileSystem(root: root)
        let file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))
        let dialogue = DialogueStore(file: file, pluginName: "Skyrim.esm")
        let quests = QuestStore(file: file, pluginName: "Skyrim.esm")
        let locator = VoiceLineLocator(dialogue: dialogue, quests: quests)

        // The most-recorded vanilla voice type, and the first line of it the
        // records resolve to a file that is really in the archives. Nothing is
        // hardcoded but the voice type: the point of the test is that the path
        // comes out of the INFO plus the speaker's voice type, so picking the
        // line by walking the records is the assertion, not a shortcut.
        let voiceType = try #require(dialogue.voiceType(editorID: "FemaleEvenToned"))
        let voiceTypeID = try #require(voiceType.editorID)
        let resolved = try #require(
            dialogue.sortedTopics()
                .lazy
                .flatMap { dialogue.infos(for: $0.formID) }
                .flatMap { locator.lines(info: $0, voiceType: voiceTypeID) }
                .first { vfs.exists($0.path) },
            "no line resolved to a \(voiceTypeID) file in the archives"
        )

        let container = try FUZFile(data: vfs.contents(forPath: resolved.path))
        let declared = try #require(container.audio().declaredDuration)
        #expect(declared > 0)

        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2))
        let engine = await WorldAudioEngine(manualRenderingFormat: format)
        await MainActor.run { engine.isEnabled = true }
        try #require(await engine.isRunning)
        let playback = try await MainActor.run {
            try engine.playVoice(
                fuzData: vfs.contents(forPath: resolved.path),
                name: resolved.path,
                worldPosition: SIMD3(700, 0, 0)
            )
        }
        #expect(playback.duration.map { abs($0 - declared) < 0.001 } == true)

        // The decode queue fills the first buffers asynchronously; render in
        // slices and sample the clock after each, so the readings prove the
        // clock advances rather than only that it ended up somewhere.
        var readings: [Double] = []
        var peak: Float = 0
        for _ in 0 ..< 12 {
            let slice = try await MainActor.run {
                try Self.render(engine, seconds: declared / 8)
            }
            peak = max(peak, slice)
            try await Task.sleep(for: .milliseconds(20))
            if let position = await engine.playbackPosition(ofSource: playback.sourceID) {
                readings.append(position)
            }
        }
        // The clock advancing only proves time passed. This proves the line was
        // decoded and mixed: real PCM reached the offline output. It is the
        // objective half of "audible" — the subjective half is a person with
        // speakers, and the PR says which one was done.
        #expect(peak > 0.01, "the voice line rendered silence (peak \(peak))")
        #expect(readings.count > 4, "clock never reported: \(readings)")
        #expect(readings == readings.sorted(), "clock went backwards: \(readings)")
        let last = try #require(readings.last)
        #expect(last > declared * 0.5, "clock reached only \(last) of \(declared) s")

        let snapshot = await engine.statsSnapshot()
        let source = try #require(snapshot.sources.first)
        #expect(source.name == resolved.path)
        #expect(source.categoryName == AudioCategory.voice.displayName)
        #expect(source.isPositional)
        print(
            "[INFO] voice line: \(resolved.path), declared \(declared) s, "
                + "clock reached \(last) s, peak sample \(peak), "
                + "lip \(container.lipByteCount) bytes"
        )
    }

    /// Renders `seconds` of output offline and returns the peak sample
    /// magnitude it produced, so a caller can tell silence from sound.
    @MainActor
    private static func render(_ engine: WorldAudioEngine, seconds: Double) throws -> Float {
        let format = engine.engine.manualRenderingFormat
        let chunk = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096))
        var rendered = 0
        var peak: Float = 0
        let target = Int(seconds * format.sampleRate)
        while rendered < target {
            let request = AVAudioFrameCount(min(4096, target - rendered))
            let status = try engine.engine.renderOffline(request, to: chunk)
            guard status == .success, chunk.frameLength > 0 else { break }
            rendered += Int(chunk.frameLength)
            guard let channels = chunk.floatChannelData else { continue }
            for channel in 0 ..< Int(format.channelCount) {
                for frame in 0 ..< Int(chunk.frameLength) {
                    peak = max(peak, abs(channels[channel][frame]))
                }
            }
        }
        return peak
    }

    /// The `<8 hex formid>_<response>.fuz` tail, which identifies the response
    /// independently of the quest and topic halves of the name.
    private static func tail(of name: String) -> String {
        let parts = name.split(separator: "_")
        guard parts.count >= 2 else { return name }
        return parts.suffix(2).joined(separator: "_")
    }

    private static func writeReport(_ report: String, named name: String) throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "logs/voice-sweep", directoryHint: .isDirectory)
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "")
        let run = root.appending(path: stamp, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: run, withIntermediateDirectories: true)
        try (report + "\n").write(
            to: run.appending(path: "\(name).txt"), atomically: true, encoding: .utf8
        )
        print("[INFO] voice \(name) report: \(run.path())")
    }
}
