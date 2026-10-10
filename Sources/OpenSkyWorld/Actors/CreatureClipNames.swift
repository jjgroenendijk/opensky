// Where a creature keeps its clips, and which file names stand for idle, walk, and run.
// Creatures name these clips differently, so each is an ordered list of candidates.
// The names come from a census of the install's archives, not from memory.
// See docs/engine/actor-animation.md.

import OpenSkyPhysics

nonisolated enum CreatureClipNames {
    /// The creature folder and the skeleton variant, from the folder that holds the
    /// skeleton: `canine\character assets wolf\` gives `meshes\actors\canine\` and `wolf`.
    struct Location: Equatable {
        let root: String
        let variant: String?
    }

    static func location(skeletonMeshPath path: String) -> Location? {
        let parts = path.split(separator: "\\", omittingEmptySubsequences: false)
        guard
            parts.count > 3, parts[0] == "meshes", parts[1] == "actors", parts[2] != "character",
            let assets = parts.indices.dropFirst(3).first(where: { isAssetsFolder(parts[$0]) }),
            assets == parts.count - 2
        else { return nil }
        let variant = parts[assets].dropFirst(variantPrefix.count)
        let root = parts[..<assets].joined(separator: "\\") + "\\"
        return Location(root: root, variant: variant.isEmpty ? nil : String(variant))
    }

    /// Clip paths to try in order for one creature: a variant clip (`mt_idle_wolf.hkx`)
    /// before the shared one (`mt_idle.hkx`).
    static func paths(_ names: [String], at location: Location) -> [String] {
        names.flatMap { name in
            let shared = location.root + "animations\\" + name + ".hkx"
            guard let variant = location.variant else { return [shared] }
            return [location.root + "animations\\" + name + "_" + variant + ".hkx", shared]
        }
    }

    static func gait(_ gait: LocomotionGait) -> [String] {
        switch gait {
        case .walk: walk + run
        case .run, .sprint: run + walk
        case .sneak, .swim: []
        }
    }

    static let idle = [
        "idle", "mt_idle", "mtidle", "mainidle", "mtidle_standing", "ww_idlebase",
        "netch_idle", "ground_combatidle", "combat_idle"
    ]

    static let walk = [
        "walkforward", "mt_walkforward", "mtwalkforward", "walkf", "mt_walkf", "mt_walk_f",
        "forward_walk", "forwardwalk", "slowf", "mtforward", "mt_forward", "mtforwardground",
        "swim_forward", "ww_walkforward", "combat_forward", "rootf"
    ]

    static let run = [
        "runforward", "mt_runforward", "mtrunforward", "runf", "mt_runf", "mt_run_f",
        "forward_run", "mtfastforward", "mt_fastforward", "swim_fastforward", "ww_runforward",
        "netch_runforward", "combat_fastforward"
    ]

    private static let variantPrefix = "character assets "

    private static func isAssetsFolder(_ part: Substring) -> Bool {
        part == "characterassets" || part == "character assets" || part.hasPrefix(variantPrefix)
    }
}
