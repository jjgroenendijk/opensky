// Every CAMS camera mesh on the install decodes into a camera track. The key
// types, play windows, and eye offsets go to `.logs/camera-tracks.log`.
// Run with `make test-real T='NIFCameraTrackRealDataTests'`.

import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyFormatsMesh
@testable import OpenSkyGameData
import Testing

struct NIFCameraTrackRealDataTests {
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func decodesEveryCameraMesh() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let store = try CameraPathStore(plugins: VanillaMasters.load(root: root))
        let vfs = VirtualFileSystem(root: root)
        let paths = Set(store.shots.records.compactMap { $0.record.model?.path.lowercased() })
        var lines: [String] = []
        var failures: [String] = []
        var missing: [String] = []
        var animated = 0
        var keyTypes: [String: Int] = [:]
        for path in paths.sorted() {
            guard let data = try? vfs.contents(forPath: "meshes\\" + path) else {
                missing.append("  \(path): not in the archives")
                continue
            }
            do {
                let file = try NIFFile(data: data)
                let track = try NIFCameraTrack(file: file)
                let rotation = track.keys?.rotationType.map { "\($0)" } ?? "none"
                keyTypes[rotation, default: 0] += 1
                animated += track.keys?.translations.isEmpty == false ? 1 : 0
                let start = track.translation(at: track.startTime)
                let end = track.translation(at: track.stopTime)
                lines.append(
                    "  \(path): \(track.startTime)...\(track.stopTime) s, "
                        + "\(track.keys?.translations.count ?? 0) moves, "
                        + "\(track.keys?.rotations.count ?? 0) turns (\(rotation)), "
                        + "eye \(Self.text(start)) -> \(Self.text(end)), "
                        + String(format: "fov %.0f", track.horizontalFieldOfView * 180 / .pi)
                )
            } catch {
                failures.append("  \(path): \(error)")
            }
        }
        let summary = [
            "[INFO] camera meshes \(paths.count), missing \(missing.count), "
                + "decoded \(paths.count - missing.count - failures.count), with moves \(animated)",
            "[INFO] rotation key types \(keyTypes.sorted { $0.key < $1.key })"
        ]
        let text = (summary + missing + failures + lines).joined(separator: "\n")
        print(text)
        try text.write(
            to: RepositoryLogs.directory().appending(path: "camera-tracks.log"),
            atomically: true,
            encoding: .utf8
        )
        #expect(failures.isEmpty, "\(failures.count) camera meshes failed")
        #expect(animated > paths.count / 2, "most camera meshes should move")
        #expect(paths.count > 20)
    }

    private static func text(_ value: SIMD3<Float>) -> String {
        String(format: "(%.0f, %.0f, %.0f)", value.x, value.y, value.z)
    }
}
