// `audio aac-check`: the objective listening check for AAC in the audio cache.
// Measures a fixed sample of each sound category and prints the verdict per
// category (docs/engine/asset-cache.md, "Audio").

import Foundation
import OpenSkyAssetCache
import OpenSkyAudio
import OpenSkyGameData

enum AudioAACCheck {
    static func run(context: CLIContext, scanner: inout ArgumentScanner) throws {
        let perCategory = try scanner.option("--per-category").map { text in
            guard let value = Int(text), value > 0 else {
                throw CLIError.usage("--per-category needs a positive whole number")
            }
            return value
        } ?? 40
        let out = try scanner.option("--out")
        try scanner.finish()
        let files = context.makeFileSystem()
        let converter = CachedAudioConverter()
        let paths = files.archiveEntries().map(\.path).filter { converter.accepts(path: $0) }
        var rows = ["category\tpath\tframes\tmean dB\tover 2 dB\tover 4 dB\tbest lag\ttransparent"]
        var failures = 0
        var otherRates = 0
        for (category, sample) in AACTransparency.sample(paths: paths, perCategory: perCategory)
            .sorted(by: { $0.key.rawValue < $1.key.rawValue })
        {
            var measured: [SpectralDistortion] = []
            for path in sample {
                do {
                    let audio = try CachedAudioConverter.decode(files.contents(forPath: path))
                    guard
                        audio.frameCount > 0,
                        audio.duration <= CachedAudioConverter.maximumSeconds
                    else { continue }
                    guard CachedAudioConverter.aacSampleRates.contains(audio.sampleRate) else {
                        otherRates += 1
                        continue
                    }
                    let result = try AACTransparency.measure(audio)
                    measured.append(result)
                    rows.append([
                        category.rawValue, path, "\(result.frames)",
                        String(format: "%.3f", result.meanDB),
                        String(format: "%.4f", result.over2DBShare),
                        String(format: "%.4f", result.over4DBShare),
                        "\(result.bestLag)", "\(result.isTransparent)"
                    ].joined(separator: "\t"))
                } catch {
                    failures += 1
                    printError("[ERROR] \(path): \(error)")
                }
            }
            report(category: category, measured: measured)
        }
        print("[INFO] \(otherRates) sampled sounds use a rate AAC does not define; they stay ALAC")
        if let out {
            try (rows.joined(separator: "\n") + "\n").write(
                toFile: out,
                atomically: true,
                encoding: .utf8
            )
            print("[INFO] wrote \(rows.count - 1) rows -> \(out)")
        }
        guard failures == 0 else {
            throw CLIError.failure("\(failures) sounds did not decode or encode")
        }
    }

    private static func report(category: AssetSoundCategory, measured: [SpectralDistortion]) {
        let passing = measured.count(where: \.isTransparent)
        let worst = measured.map(\.meanDB).max() ?? 0
        let average = measured.map(\.meanDB).reduce(0, +) / Double(max(1, measured.count))
        let verdict = !measured.isEmpty && passing == measured.count ? "AAC" : "ALAC"
        print(String(
            format: "[INFO] %@: %d sounds, %d transparent, "
                + "mean SD avg %.2f dB, worst %.2f dB -> %@",
            category.rawValue, measured.count, passing, average, worst, verdict
        ))
    }
}
