// Env-gated footstep chain over the user's own Skyrim SE install (read-only
// external input, never committed — AGENTS.md "Legal & IP"), issue #352.
//
// The synthetic suites prove the decoders and the routing in isolation. The
// claim they cannot make is the one that matters: that walking the *vanilla*
// player graph fires tags the *vanilla* footstep sets answer to, and that those
// tags reach real audio files. Both ends have to come from the install or the
// whole feature is a well-tested no-op.
//
// Skips automatically when OPENSKY_DATA_ROOT is unset. Run with
// `make realtest T='FootstepRealDataTests/vanillaGraphFiresTagsTheVanillaSetAnswers()'`.

import Foundation
@testable import opensky
import simd
import Testing

struct FootstepRealDataTests {
    private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    /// The vanilla humanoid sets, and the number of footsteps each carries per
    /// non-swimming gait. Probed 2026-08-04 through `openskycli footstep`; a
    /// load order that changes them is a real difference worth failing on.
    private static let humanoidSets = [
        "DefaultFootstepSet", "FSTBarefootFootstepSet",
        "FSTArmorLightFootstepSet", "FSTArmorHeavyFootstepSet"
    ]

    @Test(.enabled(if: Self.dataRoot != nil))
    func vanillaSetsResolveTheirTagsToRealAudioFiles() throws {
        let root = try #require(Self.dataRoot)
        let file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))
        let store = FootstepStore(file: file)
        let sounds = SoundRecordStore(file: file)
        let vfs = VirtualFileSystem(root: root)

        for editorID in Self.humanoidSets {
            let set = try #require(
                store.sets.values.first { $0.editorID == editorID },
                "\(editorID) is missing from this load order"
            )
            // Swimming is empty in every vanilla humanoid set, so a swimming
            // player is silent underfoot in the data as well as in OpenSky.
            #expect(set.footsteps(for: .swimming).isEmpty)
            for gait in [FootstepGait.walking, .running, .sprinting, .sneaking] {
                let tags = store.tags(for: gait, in: set)
                #expect(!tags.isEmpty, "\(editorID) \(gait) carries no tags")
                for tag in tags {
                    let resolved = try #require(
                        store.resolve(tag: tag, gait: gait, in: set),
                        "\(editorID) \(gait) \(tag) resolves to no sound"
                    )
                    let path = try #require(
                        try sounds.resolveAny(resolved.sound).filePaths.first,
                        "\(editorID) \(gait) \(tag) reaches a SNDR with no track"
                    )
                    let data = try vfs.contents(forPath: path)
                    // The chain ends at RIFF/WAVE, not xWMA — the finding that
                    // made issue #352 need a PCM reader at all.
                    #expect(WorldAudioEngine.isWAV(data), "\(path) is not RIFF/WAVE")
                    _ = try WorldAudioEngine.makeBuffer(wav: data, downmixToMono: true)
                }
            }
        }
    }

    /// The player's own outfit decides the set: vanilla `Player` (`NPC_
    /// 00000007`) wears iron boots, whose `ARMA.SNDD` names the heavy-armor set.
    @Test(.enabled(if: Self.dataRoot != nil))
    func thePlayersBootsSelectTheirFootstepSet() throws {
        let root = try #require(Self.dataRoot)
        let file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))
        let store = FootstepStore(file: file)
        let appearance = try ActorTemplateResolver.build(from: file, localized: true)
            .resolve(base: PlayerBody.baseFormID)
        let visual = try ActorVisualResolver.build(
            from: file,
            localized: true,
            pluginName: "Skyrim.esm"
        ).resolve(appearance: appearance)

        let feet = visual.parts.filter { $0.slots.contains(.feet) }.map(\.armature)
        #expect(!feet.isEmpty, "the player resolved no armature on its feet")
        let set = try #require(store.set(forArmatures: feet))
        #expect(set.editorID == "FSTArmorHeavyFootstepSet")
    }

    /// Drives the real graph through a second of walking and checks that at
    /// least one of the tags the vanilla default set answers to came back
    /// through the drain. This is the whole feature's load-bearing claim.
    @Test(.enabled(if: Self.dataRoot != nil))
    func vanillaGraphFiresTagsTheVanillaSetAnswers() throws {
        let root = try #require(Self.dataRoot)
        let file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))
        let store = FootstepStore(file: file)
        let set = try #require(store.defaultSet)
        let answerable = Set(store.tags(for: .walking, in: set))
        #expect(!answerable.isEmpty)

        let bridge = try Self.drivenBridge(root: root)
        let fired = Set(bridge.graphEvents.drain())

        #expect(!fired.isEmpty, "the vanilla graph fired no named events at all")
        let footsteps = fired.intersection(answerable)
        let detail = "walking fired \(fired.sorted()), none of which "
            + "\(set.editorID ?? "the set") answers to (\(answerable.sorted()))"
        #expect(!footsteps.isEmpty, "\(detail)")
    }

    /// The material half of the chain (issue #358) against the real plugin:
    /// every vanilla `MATT` is reachable from a collision mesh by its hash, the
    /// landscape textures name materials, and naming one takes the same tag to a
    /// different sound than the representative fallback does.
    @Test(.enabled(if: Self.dataRoot != nil))
    func vanillaMaterialsResolveAndChangeTheSound() throws {
        let root = try #require(Self.dataRoot)
        let file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))
        let materials = MaterialTypeIndex(file: file)
        let store = FootstepStore(file: file)
        let sounds = SoundRecordStore(file: file)

        #expect(!materials.isEmpty, "this load order carries no MATT records")
        // A material with no MNAM could never be reached from a mesh; vanilla
        // names every one of them.
        #expect(materials.hashedMaterialCount == materials.materials.count)
        let snow = try #require(
            materials.materials.values.first { $0.editorID == "MaterialSnow" },
            "MaterialSnow is missing from this load order"
        )
        let havok = try #require(snow.havokMaterial)
        #expect(materials.material(forHavokMaterial: havok) == snow.formID)

        let set = try #require(store.defaultSet)
        let fallback = try #require(store.resolve(tag: "FootLeft", gait: .walking, in: set))
        let onSnow = try #require(
            store.resolve(tag: "FootLeft", gait: .walking, in: set, material: snow.formID)
        )
        #expect(onSnow.impact.formID != fallback.impact.formID)
        let path = try #require(try sounds.resolveAny(onSnow.sound).filePaths.first)
        #expect(path.lowercased().contains("snow"), "snow resolved to \(path)")
        _ = try WorldAudioEngine.makeBuffer(
            wav: VirtualFileSystem(root: root).contents(forPath: path),
            downmixToMono: true
        )
    }

    /// Exterior ground names its material through `LTEX.MNAM` rather than
    /// through Havok, so the landscape textures have to resolve too — and a
    /// snowy one has to reach a snow material, or terrain footsteps would be
    /// resolvable but wrong.
    @Test(.enabled(if: Self.dataRoot != nil))
    func landscapeTexturesNameTheirMaterials() throws {
        let root = try #require(Self.dataRoot)
        let file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))
        let materials = MaterialTypeIndex(file: file)
        let group = try #require(file.topGroup(of: "LTEX"))

        var textures: [LandTexture] = []
        for case let .record(record) in try group.children()
            where record.type == "LTEX" && !record.isDeleted
        {
            if let texture = try? LandTexture(record: record) {
                textures.append(texture)
            }
        }
        #expect(!textures.isEmpty, "this load order carries no LTEX records")

        let named = textures.count { materials.material(forLandTexture: $0.formID) != nil }
        #expect(named > 0, "no LTEX in this load order names a MATT")

        // Skyrim is a snowy province, so at least one landscape texture has to
        // reach a snow material. A chain that resolved every texture to the
        // same material would pass the count above and fail this.
        let snowy = textures.contains { texture in
            guard let material = materials.material(forLandTexture: texture.formID) else {
                return false
            }
            return materials.describe(material).lowercased().contains("snow")
        }
        #expect(snowy, "no landscape texture reaches a snow material")
    }

    // MARK: - Loading

    /// A bridge over the real graph and the launch cell's real terrain, walked
    /// forward for a second of fixed steps with its event queue undrained.
    private static func drivenBridge(root: GameDataRoot) throws -> LocomotionBridge {
        let vfs = VirtualFileSystem(root: root)
        // `PlayerBehaviorGraph.load` rather than a hand-built instance, because
        // it is what wires `references`: `0_master.hkx` is a shell whose
        // locomotion branch is a `hkbBehaviorReferenceGenerator` naming
        // `mt_behavior.hkx`, and the `FootLeft`/`FootRight` clip triggers live
        // in that referenced file. A graph built without a reference source
        // reaches only `0_master`'s own states, so it fires transition events
        // such as `MTState` and never a footstep tag (issues #385 and #394).
        let graph = try PlayerBehaviorGraph.load(fileSystem: vfs).instance
        let configuration = PlayerMovementConfiguration.resolve(
            store: GameSettingLoader.load(root: root),
            movementTypes: MovementTypeLoader.load(root: root)
        )
        let terrain = try #require(LocomotionRealTerrain.terrainField(root: root))
        let harness = LocomotionDriveHarness(
            bridge: LocomotionBridge(configuration: configuration, graph: graph),
            terrain: terrain,
            start: LocomotionRealTerrain.startPosition(on: terrain)
        )
        graph.activate()
        // The queue is bounded, so a long walk would drop the earliest steps;
        // one second at 120 Hz stays well inside it.
        _ = harness.run(
            input: CameraInput(moveForward: 1, dt: LocomotionDriveHarness.step),
            steps: LocomotionDriveHarness.secondOfSteps,
            label: "footsteps"
        )
        return harness.bridge
    }
}
