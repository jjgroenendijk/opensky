// Env-gated lip-sync render evidence over a real archive track and a real
// actor face. Six PNGs and a numeric report remain under gitignored `logs/`.

import Foundation
@testable import OpenSkyAudio
@testable import OpenSkyRendering
@testable import OpenSkyWorld
import TagsTesting
import Testing

@Suite(.tags(.gpu))
struct LipSyncRenderRealDataTests {
    private static let sampleTimes: [Double] = [0.30, 11.0 / 30.0, 0.50]

    @Test(.enabled(if: RealDataEnvironment.canRender))
    @MainActor
    func threeTrackTimesChangeFacePixelsAndRepeatExactly() throws {
        let harness = try HeimskrFace.lipSyncHarness()
        var deltas: [Int] = []
        for (index, time) in Self.sampleTimes.enumerated() {
            harness.clock.publish(time)
            harness.lip.isEnabled = false
            let off = try frame(
                harness.renderer,
                time: Float(time),
                name: "lip-\(index)-off.png"
            )
            harness.lip.isEnabled = true
            let on = try frame(
                harness.renderer,
                time: Float(time),
                name: "lip-\(index)-on.png"
            )
            let repeated = try frame(harness.renderer, time: Float(time), name: nil)
            let delta = RenderedPixels.changedCount(off, on)
            deltas.append(delta)
            #expect(delta > 20, "lip sync at \(time)s changed only \(delta) pixels")
            #expect(
                RenderedPixels.changedCount(on, repeated) == 0,
                "\(time)s was not deterministic"
            )
        }
        let captures = try runDirectory.path()
        print(
            "[INFO] lip render A/B: \(HeimskrFace.voicePath), times \(Self.sampleTimes), "
                + "changed pixels \(deltas), captures \(captures)"
        )
    }

    @MainActor
    private func frame(_ renderer: Renderer, time: Float, name: String?) throws -> [UInt8] {
        let texture = try renderer.renderOffscreen(
            width: HeimskrFace.size, height: HeimskrFace.size, animationTime: time
        )
        if let name {
            try FrameScreenshot.write(texture: texture, to: runDirectory.appending(path: name))
        }
        return RenderedPixels.read(texture)
    }

    private var runDirectory: URL {
        get throws { try RepositoryLogs.createdDirectory("lip-sync-render") }
    }
}
