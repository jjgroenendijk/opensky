// Env-gated face-morph acceptance over the user's install. Associates
// Heimskr's baked FaceGen shapes with HDPT expression TRIs, renders Aah at
// zero and one, and proves a repeated one-weight frame is deterministic.

import Foundation
@testable import OpenSkyRendering
import OpenSkyTagsTesting
@testable import OpenSkyWorld
import Testing

@Suite(.tags(.gpu))
struct FaceMorphRenderRealDataTests {
    @Test(.enabled(if: RealDataEnvironment.canRender))
    @MainActor
    func expressionWeightChangesPixelsAndRepeatsDeterministically() throws {
        let face = try HeimskrFace.load()
        let playback = face.playback

        try #require(
            playback.bindings.count >= 2,
            "Face morph association misses: \(playback.misses)"
        )
        try #require(playback.targetNames.contains("Aah"))
        #expect(playback.pairedPaths.contains {
            $0.lowercased().hasSuffix("malehead.tri")
        })
        #expect(playback.pairedPaths.contains {
            $0.lowercased().hasSuffix("mouthhuman.tri")
        })

        let renderer = try face.renderer(animations: [playback])

        let baseline = try frame(renderer, name: "face-morph-zero.png")
        #expect(playback.setWeight(1, for: "Aah"))
        let morphed = try frame(renderer, name: "face-morph-aah.png")
        let repeated = try frame(renderer, name: nil)
        let delta = RenderedPixels.changedCount(baseline, morphed)

        #expect(delta > 20, "Aah changed only \(delta) pixels")
        #expect(RenderedPixels.changedCount(morphed, repeated) == 0)
        print(
            "[INFO] Face morph A/B: \(playback.bindings.count) pairs, "
                + "\(playback.targetNames.count) targets, \(delta) changed pixels"
        )
    }

    @MainActor
    private func frame(_ renderer: Renderer, name: String?) throws -> [UInt8] {
        let texture = try renderer.renderOffscreen(
            width: HeimskrFace.size, height: HeimskrFace.size, animationTime: 0
        )
        if let name {
            try FrameScreenshot.write(
                texture: texture,
                to: runDirectory.appending(path: name)
            )
        }
        return RenderedPixels.read(texture)
    }

    private var runDirectory: URL {
        get throws { try RepositoryLogs.createdDirectory("face-morph-render") }
    }
}
