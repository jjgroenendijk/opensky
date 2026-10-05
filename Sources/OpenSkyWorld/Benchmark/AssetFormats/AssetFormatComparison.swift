// Loads each sampled asset the current way and from every cache candidate,
// and measures time, memory, disk size, and the difference from the original.
// Cache files go to a scratch folder and are deleted after each candidate
// (docs/tools/asset-format-comparison.md).

import Foundation
import Metal
import OpenSkyGameData
import OpenSkyRendering

public final class AssetFormatComparison {
    /// One load of one row. `mismatch` names loaded bytes that differ from the payload.
    struct Sample {
        let timing: AssetLoadTiming
        let memoryBytes: Int
        var mismatch: String?
    }

    let files: any GameFileSource
    let storedSize: (String) -> Int?
    let device: MTLDevice
    let readback: TextureReadback
    let io: AssetFileLoader
    let textureLoader: TextureLoader
    let scratch: URL
    let plan: AssetFormatComparisonPlan
    /// Called with each asset path before it is measured.
    public var progress: ((String) -> Void)?
    private var fileCounter = 0

    /// - Parameter storedSize: the bytes an archive stores for a path, when known.
    public init(
        files: any GameFileSource,
        storedSize: @escaping (String) -> Int?,
        device: MTLDevice,
        library: MTLLibrary,
        scratch: URL,
        plan: AssetFormatComparisonPlan = .standard
    ) throws {
        self.files = files
        self.storedSize = storedSize
        self.device = device
        readback = try TextureReadback(device: device, library: library)
        io = try AssetFileLoader(device: device)
        textureLoader = try TextureLoader(device: device)
        self.scratch = scratch
        self.plan = plan
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    /// - Parameter census: the install's size, for the whole-game estimate.
    public func run(
        machine: BenchmarkMachine,
        census: AssetCensus? = nil
    ) -> AssetFormatComparisonResult {
        let startedAt = Date()
        let startLoad = Self.loadAverage()
        let assets = plan.entries.map { entry in
            progress?(entry.path)
            return measure(entry)
        }
        return AssetFormatComparisonResult(
            startedAt: startedAt,
            machine: machine,
            loadAverage: [startLoad, Self.loadAverage()],
            plan: plan,
            assets: assets,
            census: census
        )
    }

    private func measure(_ entry: AssetSampleEntry) -> AssetMeasurement {
        do {
            switch entry.kind {
            case .texture: return try measureTexture(entry)
            case .mesh: return try measureMesh(entry)
            case .collision: return try measureCollision(entry)
            case .animation: return try measureAnimation(entry)
            case .audio: return try measureAudio(entry)
            }
        } catch {
            return AssetMeasurement(
                entry: entry, detail: "", candidates: [], error: String(describing: error)
            )
        }
    }

    // MARK: - Shared measuring steps

    static func timed<T>(_ body: () throws -> T) rethrows -> (T, Double) {
        let start = DispatchTime.now().uptimeNanoseconds
        let value = try body()
        return (value, Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6)
    }

    /// Runs `load` `plan.repeats` times and keeps the run with the median total.
    func medianRun(_ load: () throws -> Sample) throws -> Sample {
        var samples: [Sample] = []
        for _ in 0 ..< max(1, plan.repeats) {
            try samples.append(load())
        }
        samples.sort { $0.timing.totalMS < $1.timing.totalMS }
        return samples[samples.count / 2]
    }

    /// The current engine load from the archive.
    func originalRow(
        _ entry: AssetSampleEntry,
        sourceBytes: Int,
        load: () throws -> Sample
    ) throws -> AssetCandidateMeasurement {
        let sample = try medianRun(load)
        return AssetCandidateMeasurement(
            candidate: "original", storage: nil, path: .archive, timing: sample.timing,
            sizes: (sample.memoryBytes, storedSize(entry.path) ?? sourceBytes),
            fidelity: .lossless
        )
    }

    /// Writes `payload` once per storage and measures each load path on it.
    func cacheRows(
        candidate: String,
        payload: Data,
        convertMS: Double = 0,
        storages: [AssetFileStorage] = AssetFileStorage.allCases,
        paths: [AssetLoadPath],
        fidelity: AssetFidelity,
        load: (AssetLoadPath, URL, AssetFileStorage) throws -> Sample
    ) -> [AssetCandidateMeasurement] {
        storages.flatMap { storage in
            let url = nextScratchURL(storage)
            defer { try? FileManager.default.removeItem(at: url) }
            let disk: Int
            let writeMS: Double
            do {
                (_, writeMS) = try Self.timed {
                    try AssetFileLoader.write(payload, to: url, storage: storage)
                }
                disk = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            } catch {
                return paths.map { failedRow(candidate, storage, $0, String(describing: error)) }
            }
            return paths.map { path in
                do {
                    let sample = try medianRun { try load(path, url, storage) }
                    return AssetCandidateMeasurement(
                        candidate: candidate, storage: storage, path: path,
                        timing: sample.timing, sizes: (sample.memoryBytes, disk),
                        fidelity: fidelity, convertMS: convertMS, writeMS: writeMS,
                        error: sample.mismatch
                    )
                } catch {
                    return failedRow(candidate, storage, path, String(describing: error))
                }
            }
        }
    }

    /// The scratch path for a cache file a measurement owns until it returns.
    func nextScratchURL(_ storage: AssetFileStorage) -> URL {
        fileCounter += 1
        return scratch.appending(path: "\(fileCounter).\(storage.rawValue)")
    }

    private func failedRow(
        _ candidate: String,
        _ storage: AssetFileStorage,
        _ path: AssetLoadPath,
        _ error: String
    ) -> AssetCandidateMeasurement {
        AssetCandidateMeasurement(
            candidate: candidate, storage: storage, path: path,
            timing: AssetLoadTiming(readMS: 0, decodeMS: 0, uploadMS: 0),
            sizes: (0, 0), fidelity: AssetFidelity(exact: false), error: error
        )
    }

    /// Reads a cache file on the CPU: mapped when raw, decompressed through MTLIO otherwise.
    func readCacheFile(_ url: URL, _ storage: AssetFileStorage, byteCount: Int) throws -> Data {
        if storage == .raw {
            return try Data(contentsOf: url, options: .alwaysMapped)
        }
        return try io.read(url, storage: storage, byteCount: byteCount)
    }

    static func loadAverage() -> Double {
        var values = [Double](repeating: 0, count: 3)
        return getloadavg(&values, 3) > 0 ? values[0] : 0
    }
}
