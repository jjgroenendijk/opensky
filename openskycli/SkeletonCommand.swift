// `skeleton <hkx-key> [--nif <nif-key>]`: decode every hkaSkeleton in a Havok
// packfile (todo 6.2) — bone names, parent chain, root count — and, with
// --nif, name-map the rig onto the NIF skeleton's NiNode names bind-pose
// skinning keys on, reporting matches + reason-tagged mismatches both
// directions. Same parsers the engine uses (HKASkeleton, SkeletonBoneMap,
// NIFSkeleton), so a mismatch here is what animation loading will see. CLI
// parses args + prints only; the logic is unit-tested in openskyTests.

import Foundation

enum SkeletonCommand {
    /// Cap the per-skeleton bone dump so a 99-bone rig stays greppable.
    private static let boneListLimit = 12

    static func run(context: CLIContext, scanner: inout ArgumentScanner) throws {
        let nifKey = try scanner.option("--nif")
        let key = try scanner.positional("key")
        try scanner.finish()

        let fileSystem = context.makeFileSystem()
        let skeletons: [HKASkeleton]
        do {
            let file = try HKXFile(data: fileSystem.contents(forPath: key))
            skeletons = try HKASkeleton.skeletons(in: file)
        } catch {
            throw CLIError.failure("cannot decode \(key): \(String(describing: error))")
        }
        print("[INFO] \(key): \(skeletons.count) hkaSkeleton object(s)")
        for (index, skeleton) in skeletons.enumerated() {
            printSkeleton(index: index, skeleton: skeleton)
        }

        guard let nifKey else { return }
        try printNameMap(skeletons: skeletons, nifKey: nifKey, fileSystem: fileSystem)
    }

    private static func printSkeleton(index: Int, skeleton: HKASkeleton) {
        let name = skeleton.name ?? "<unnamed>"
        print("skeleton \(index) \"\(name)\": \(skeleton.boneCount) bones, "
            + "\(skeleton.rootIndices.count) roots")
        for boneIndex in 0 ..< min(skeleton.boneCount, boneListLimit) {
            let parent = skeleton.parentIndices[boneIndex]
            print("  bone \(boneIndex) \"\(skeleton.boneNames[boneIndex])\" parent \(parent)")
        }
        let hidden = skeleton.boneCount - min(skeleton.boneCount, boneListLimit)
        if hidden > 0 {
            print("  ... \(hidden) more bones")
        }
    }

    /// Name-maps the rig (most bones) onto the NIF nodes. Ragdoll/other
    /// skeletons are physics, not the mesh bind rig, so they are summarized
    /// but not mapped.
    private static func printNameMap(
        skeletons: [HKASkeleton],
        nifKey: String,
        fileSystem: VirtualFileSystem
    ) throws {
        guard
            let rig = skeletons.enumerated()
                .max(by: { $0.element.boneCount < $1.element.boneCount })
        else {
            throw CLIError.failure("no hkaSkeleton to map onto \(nifKey)")
        }
        let nifNodeNames: Set<String>
        do {
            let nif = try NIFFile(data: fileSystem.contents(forPath: nifKey))
            nifNodeNames = try Set(NIFSkeleton(file: nif).boneTransforms.keys)
        } catch {
            throw CLIError.failure("cannot decode \(nifKey): \(String(describing: error))")
        }
        let map = SkeletonBoneMap(
            hkxBoneNames: rig.element.boneNames,
            nifNodeNames: nifNodeNames
        )
        print("name-map skeleton \(rig.offset) (rig) vs \(nifKey): "
            + "\(map.matchedCount) of \(rig.element.boneCount) matched, "
            + "\(nifNodeNames.count) NIF nodes")
        for mismatch in map.unmatchedHKX {
            print("  unmatched hkx bone \"\(mismatch.name)\" -> \(mismatch.reason)")
        }
        for mismatch in map.unmatchedNIF {
            print("  unmatched nif node \"\(mismatch.name)\" -> \(mismatch.reason)")
        }
    }
}
