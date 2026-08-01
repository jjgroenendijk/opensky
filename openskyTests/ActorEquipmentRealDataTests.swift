// Env-gated M12.2.1 acceptance over the user's read-only Skyrim SE install:
// resolve a dressed vanilla NPC before and after an equip, and render both.
//
// The before frame is the actor as the plugin dresses him — his DOFT outfit.
// The after frame is the same actor resolved from a runtime equipped set that
// swaps his torso piece and puts a weapon in his hand. Both frames go to
// gitignored `logs/` and are linked from the PR; a rendered frame embeds the
// user's own assets, so it is game content and never committed (AGENTS.md
// "Legal & IP boundary").
//
// Run with `make realtest T='ActorEquipmentRealDataTests/<name>()'`, which
// injects the data root and runs under the RSS watchdog. Plain `xcodebuild
// test` does not forward `OPENSKY_DATA_ROOT`, so this silently skips there.

import CoreGraphics
import Foundation
import Metal
import MetalKit
@testable import opensky
import simd
import Testing

struct ActorEquipmentRealDataTests {
    private static let device: MTLDevice? = {
        guard
            let device = MTLCreateSystemDefaultDevice(),
            device.supportsFamily(.metal4)
        else { return nil }
        return device
    }()

    private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    private static var canRun: Bool {
        device != nil && dataRoot != nil
    }

    /// Heimskr, the Whiterun street preacher — the same ACHR the M5.4
    /// acceptance renders, so the two frames are directly comparable.
    private static let heimskrACHR = FormID(0x0001_A682)
    /// `ArmorIronCuirass`, a torso piece his monk robes do not overlap by
    /// accident: both claim biped slot 32, which is what makes the swap
    /// visible rather than a second layer.
    private static let ironCuirass = FormID(0x0001_2E49)
    /// `IronSword`, the vanilla one-handed sword.
    private static let ironSword = FormID(0x0001_2EB7)

    @Test(.enabled(if: Self.canRun))
    @MainActor
    func resolvesADressedNPCBeforeAndAfterAnEquip() throws {
        let device = try #require(Self.device)
        let root = try #require(Self.dataRoot)
        let file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))
        let record = try #require(ESMWalk.record(withFormID: Self.heimskrACHR.rawValue, in: file))
        let actor = try PlacedActor(record: record)

        let appearance = try ActorTemplateResolver.build(from: file, localized: true)
            .resolve(base: actor.base)
        let resolver = ActorVisualResolver.build(
            from: file, localized: true, pluginName: "Skyrim.esm"
        )

        // The catalog must describe both items, or the rest of the test is
        // asserting against an engine that simply found nothing.
        let cuirass = try #require(resolver.equipment.item(Self.ironCuirass))
        let sword = try #require(resolver.equipment.item(Self.ironSword))
        #expect(cuirass.occupancy.slots.contains(.body))
        #expect(sword.occupancy.hands == .rightHand)
        #expect(sword.modelPath != nil)

        let before = try resolver.resolve(appearance: appearance)
        let after = try resolver.resolve(
            appearance: appearance, equipped: [Self.ironCuirass, Self.ironSword]
        )

        #expect(!before.usesRuntimeEquipment)
        #expect(before.attachments.isEmpty)
        #expect(after.usesRuntimeEquipment)
        #expect(after.attachments.count == 1)
        #expect(after.attachments.first?.bone == ActorAttachmentBone.drawnWeapon)

        // The equipped set replaced the outfit: his robes are gone and the
        // cuirass is on. Model paths are compared lowercased because plugin
        // records and archive entries disagree on case.
        let beforePaths = Set(before.parts.map { $0.modelPath.lowercased() })
        let afterPaths = Set(after.parts.map { $0.modelPath.lowercased() })
        #expect(beforePaths.contains { $0.contains("monkrobes") })
        #expect(!afterPaths.contains { $0.contains("monkrobes") })
        #expect(afterPaths.contains { $0.contains("cuirass") })

        // The cuirass claims slot 32, so covered skin stays masked — the same
        // rule the plugin outfit path already obeyed.
        #expect(after.equippedSlots.contains(BodySlots.body))
        #expect(after.skips.contains { $0.reason == AppearanceSkip.Reason.maskedByOutfit })

        let vfs = VirtualFileSystem(root: root)
        let textures = TextureLibrary(fileSystem: vfs, device: device)
        let meshes = MeshLibrary(fileSystem: vfs, device: device, textures: textures)
        let assembler = ActorAssembler(provider: meshes)

        let beforeAssembly = assembler.assemble(placed: actor, visual: before)
        let afterAssembly = assembler.assemble(placed: actor, visual: after)
        #expect(beforeAssembly.isRenderable)
        #expect(afterAssembly.isRenderable)
        // The weapon loaded, through the attachment path, as its own model.
        let hasAttachment = afterAssembly.models.contains { model in
            if case .attachment = model.role {
                return true
            }
            return false
        }
        #expect(hasAttachment)

        try render(beforeAssembly, device: device, to: "actor-equip-before.png")
        try render(afterAssembly, device: device, to: "actor-equip-after.png")
    }

    /// The attachment's skinning palette must name the rig's `Weapon` bone, or
    /// the weapon will never move with the hand at runtime. Checked against the
    /// real vanilla skeleton, because the bone name is observed data.
    @Test(.enabled(if: Self.canRun))
    @MainActor
    func attachmentBindsToTheRealSkeletonsWeaponNode() throws {
        let device = try #require(Self.device)
        let root = try #require(Self.dataRoot)
        let vfs = VirtualFileSystem(root: root)
        let textures = TextureLibrary(fileSystem: vfs, device: device)
        let meshes = MeshLibrary(fileSystem: vfs, device: device, textures: textures)

        let skeletonPath = "meshes\\actors\\character\\character assets\\skeleton.nif"
        guard case let .success(skeleton) = meshes.loadActorSkeleton(path: skeletonPath) else {
            Issue.record("vanilla character skeleton did not load from \(skeletonPath)")
            return
        }
        // The NIF spells the node WEAPON and the Havok rig spells it Weapon;
        // the lookup folds case so the bind transform resolves either way.
        #expect(skeleton.skeleton.transform(forBoneNamed: "Weapon") != nil)
        #expect(skeleton.skeleton.transform(forBoneNamed: "WEAPON") != nil)

        let file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))
        let catalog = EquipmentCatalog.build(from: file)
        let modelPath = try #require(catalog.item(Self.ironSword)?.modelPath)

        guard
            case let .success(asset) = meshes.loadActorAttachment(
                path: modelPath, bone: ActorAttachmentBone.drawnWeapon, skeleton: skeleton
            )
        else {
            Issue.record("iron sword did not load as an attachment from \(modelPath)")
            return
        }
        let attachmentMeshes = asset.model.meshes
        // Bound before the assertion: a key-path `allSatisfy` inside `#expect`
        // expands to something the macro treats as throwing, and SwiftFormat
        // rewrites the closure form into the key-path form on every run.
        let allSkinned = attachmentMeshes.allSatisfy(\.isSkinned)
        #expect(!attachmentMeshes.isEmpty)
        #expect(allSkinned)
    }

    @MainActor
    private func render(
        _ assembly: ActorAssembly<ActorRenderAsset>,
        device: MTLDevice,
        to name: String
    ) throws {
        let bounds = try #require(assembly.worldBounds)
        let view = MTKView(
            frame: CGRect(x: 0, y: 0, width: 800, height: 800),
            device: device
        )
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        let renderer = try Renderer(
            view: view,
            scene: RenderScene(instances: assembly.renderPlacements),
            camera: SceneCamera.framing(bounds: (bounds.min, bounds.max))
        )
        let texture = try renderer.renderOffscreen(width: 800, height: 800)

        try FileManager.default.createDirectory(
            at: logsDirectory,
            withIntermediateDirectories: true
        )
        let output = logsDirectory.appending(path: name)
        try FrameScreenshot.write(texture: texture, to: output)
        print("[INFO] \(name): \(output.path)")
    }

    private var logsDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "logs")
    }
}
