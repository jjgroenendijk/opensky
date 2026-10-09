// Env-gated head assembly A/B over the user's install: Heimskr with his baked
// FaceGen head and with his head parts loaded one by one. The two silhouettes
// must agree, and the assembled head must add a head to a headless body.
// Captures go to .logs/head-assembly-render/.

import Foundation
import Metal
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyRendering
@testable import OpenSkyWorld
import simd
import TagsTesting
import Testing

@Suite(.tags(.gpu))
struct HeadAssemblyRenderRealDataTests {
    @Test(.enabled(if: RealDataEnvironment.canRender))
    @MainActor
    func assembledHeadMatchesTheBakedSilhouette() throws {
        let install = try RealDataInstall.load()
        let builder = install.sceneBuilder(readsLooseFiles: true)
        let placed = try PlacedActor(record: #require(
            ESMWalk.record(withFormID: 0x0001_A682, in: install.file)
        ))
        let resolvers = builder.actorResolversBuildingIfNeeded()
        let visual = try resolvers.visual.resolve(
            appearance: resolvers.template.resolve(base: placed.base)
        )
        let assembler = ActorAssembler(provider: install.meshes)
        let baked = assembler.assemble(placed: placed, visual: visual)
        let assembled = assembler.assemble(
            placed: placed,
            visual: visual.presenting(ActorPresentationState(headSource: .assembled))
        )
        let headParts = assembled.models.filter {
            if case .headPart = $0.role {
                return true
            }
            return false
        }
        #expect(headParts.count >= 4, "parts: \(visual.headParts.parts.map { $0.editorID ?? "?" })")
        #expect(!assembled.models.contains {
            if case .faceGenHead = $0.role {
                return true
            }
            return false
        })
        let headless = ActorAssembly(
            actor: baked.actor, visual: baked.visual, transform: baked.transform,
            models: baked.models.filter {
                if case .body = $0.role {
                    return true
                }
                return false
            },
            skips: []
        )

        let empty = try frame([], transform: baked.transform, device: install.device, name: nil)
        let body = try frame(headless, device: install.device, name: "headless.png")
        let bakedFrame = try frame(baked, device: install.device, name: "baked.png")
        let assembledFrame = try frame(assembled, device: install.device, name: "assembled.png")
        let bodyMask = Self.mask(body, against: empty)
        let bakedMask = Self.mask(bakedFrame, against: empty)
        let assembledMask = Self.mask(assembledFrame, against: empty)
        let overlap = Self.intersectionOverUnion(bakedMask, assembledMask)
        let headPixels = assembledMask.count { $0 } - bodyMask.count { $0 }
        print("[INFO] Head A/B: IoU \(overlap), head pixels \(headPixels), "
            + "\(headParts.count) parts, misses \(visual.headParts.misses)")
        #expect(overlap > 0.85, "baked and assembled silhouettes differ: IoU \(overlap)")
        // Heimskr wears a hood, so the face is a small part of the frame.
        #expect(headPixels > 400, "the assembled head added only \(headPixels) pixels")
    }

    @MainActor
    private func frame(
        _ assembly: ActorAssembly<ActorRenderAsset>,
        device: any MTLDevice,
        name: String?
    ) throws -> [UInt8] {
        try frame(
            assembly.renderPlacements, transform: assembly.transform, device: device, name: name
        )
    }

    @MainActor
    private func frame(
        _ placements: [RenderPlacement],
        transform: float4x4,
        device: any MTLDevice,
        name: String?
    ) throws -> [UInt8] {
        let renderer = try HeimskrFace.renderer(
            placements: placements, animations: [], transform: transform, device: device
        )
        let texture = try renderer.renderOffscreen(
            width: HeimskrFace.size, height: HeimskrFace.size, animationTime: 0
        )
        if let name {
            try FrameScreenshot.write(
                texture: texture,
                to: RepositoryLogs.createdDirectory("head-assembly-render").appending(path: name)
            )
        }
        return RenderedPixels.read(texture)
    }

    /// Pixels where `frame` differs from the empty scene by more than noise.
    private static func mask(_ frame: [UInt8], against empty: [UInt8]) -> [Bool] {
        stride(from: 0, to: min(frame.count, empty.count), by: 4).map { index in
            (0 ..< 3).contains { abs(Int(frame[index + $0]) - Int(empty[index + $0])) > 8 }
        }
    }

    private static func intersectionOverUnion(_ lhs: [Bool], _ rhs: [Bool]) -> Double {
        let both = zip(lhs, rhs).count { $0 && $1 }
        let either = zip(lhs, rhs).count { $0 || $1 }
        return either == 0 ? 0 : Double(both) / Double(either)
    }
}
