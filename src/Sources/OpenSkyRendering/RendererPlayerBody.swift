// The renderer's half of the third-person body. No cell owns the player, so its draw
// groups join the scene's at encode time and its GPU allocations stay resident.
// The pose comes from the behavior graph on the simulation clock
// (docs/engine/actor-animation.md).

import Metal
import OpenSkyRenderCore
import simd

extension Renderer {
    /// The lists the opaque groups join: the scene, the player's body, the effect
    /// models, and the loading cover. Order is for stable grouping only; depth decides
    /// visibility. The first-person arms are drawn separately
    /// (`RendererFirstPersonArms.swift`).
    private var opaqueSources: [[DrawGroup]] {
        let body = isPlayerBodyVisible ? frameInput.rigs.body?.render.opaque : nil
        return [scene.opaque, body ?? [], effects.scene.opaque, effects.loadingCover?.opaque ?? []]
    }

    private var alphaTestedSources: [[DrawGroup]] {
        let body = isPlayerBodyVisible ? frameInput.rigs.body?.render.alphaTested : nil
        return [
            scene.alphaTested, body ?? [], effects.scene.alphaTested,
            effects.loadingCover?.alphaTested ?? []
        ]
    }

    /// What the shadow pass rasterizes: the scene plus the player's body in
    /// every mode a player exists in, whether or not the eye can see it. The
    /// reasoning is on `PlayerRigVisibility`.
    private var shadowOpaqueSources: [[DrawGroup]] {
        let body = frameInput.rigs.visibility.castsBodyShadow ? frameInput.rigs.body?.render
            .opaque : nil
        return [scene.opaque, body ?? []]
    }

    private var shadowAlphaTestedSources: [[DrawGroup]] {
        let body = frameInput.rigs.visibility.castsBodyShadow
            ? frameInput.rigs.body?.render.alphaTested : nil
        return [scene.alphaTested, body ?? []]
    }

    /// Joins the lists once per frame, before the first pass reads them. The shadow
    /// pass reads them once per cascade, so joining on each read copied the scene lists.
    /// A list whose sources are the same as last frame keeps its joined copy.
    func refreshFrameDrawGroups() {
        frameDrawGroups.refresh(
            opaque: opaqueSources,
            alphaTested: alphaTestedSources,
            shadowOpaque: shadowOpaqueSources,
            shadowAlphaTested: shadowAlphaTestedSources
        )
    }

    /// Whether the third-person body is drawn to the camera this frame.
    var isPlayerBodyVisible: Bool {
        frameInput.rigs.visibility.drawsBody
    }

    /// Grows the draw and instance rings to cover the scene plus the body. The
    /// scene's own sizing runs in `setScene` and knows nothing about the player,
    /// so a body attached over a large scene has to ask for its own headroom.
    public func growRingsForPlayerBody(_ body: any RenderRig) throws {
        try growRings(
            drawCount: scene.drawCount + body.render.drawCount + effects.scene.drawCount,
            instanceCount: scene.instanceCount + body.render.instanceCount
                + effects.scene.instanceCount
        )
    }
}

/// The draw-group lists of one frame, as `refreshFrameDrawGroups()` joined them.
struct FrameDrawGroups {
    private var joinedOpaque = JoinedDrawGroups()
    private var joinedAlphaTested = JoinedDrawGroups()
    private var joinedShadowOpaque = JoinedDrawGroups()
    private var joinedShadowAlphaTested = JoinedDrawGroups()

    var opaque: [DrawGroup] {
        joinedOpaque.groups
    }

    var alphaTested: [DrawGroup] {
        joinedAlphaTested.groups
    }

    var shadowOpaqueCasters: ShadowCasterList {
        joinedShadowOpaque.casterList
    }

    var shadowAlphaTestedCasters: ShadowCasterList {
        joinedShadowAlphaTested.casterList
    }

    mutating func refresh(
        opaque: [[DrawGroup]],
        alphaTested: [[DrawGroup]],
        shadowOpaque: [[DrawGroup]],
        shadowAlphaTested: [[DrawGroup]]
    ) {
        joinedOpaque.refresh(opaque)
        joinedAlphaTested.refresh(alphaTested)
        joinedShadowOpaque.refresh(shadowOpaque)
        joinedShadowAlphaTested.refresh(shadowAlphaTested)
    }
}

/// One joined list and the lists it was joined from. Each source is a `let` list
/// of a render scene, which cannot change in place, and this copy keeps its
/// storage alive. So equal storage means equal contents, and a frame whose
/// sources did not change keeps the joined list without copying any group.
nonisolated struct JoinedDrawGroups {
    private(set) var groups: [DrawGroup] = []
    private(set) var casters: [Int] = []
    private var sources: [[DrawGroup]] = []

    var casterList: ShadowCasterList {
        ShadowCasterList(groups: groups, casters: casters)
    }

    mutating func refresh(_ next: [[DrawGroup]]) {
        guard !Self.sameStorage(sources, next) else { return }
        sources = next
        groups = Self.joined(next)
        casters = ShadowCasterList.casterIndices(of: groups)
    }

    /// The first source shares its storage when nothing joins it.
    private static func joined(_ lists: [[DrawGroup]]) -> [DrawGroup] {
        var count = 0
        var nonEmpty = 0
        for list in lists where !list.isEmpty {
            count += list.count
            nonEmpty += 1
        }
        if nonEmpty == 0 {
            return []
        }
        if nonEmpty == 1, let only = lists.first(where: { !$0.isEmpty }) {
            return only
        }
        var result: [DrawGroup] = []
        result.reserveCapacity(count)
        for list in lists {
            result += list
        }
        return result
    }

    private static func sameStorage(_ first: [[DrawGroup]], _ second: [[DrawGroup]]) -> Bool {
        guard first.count == second.count else { return false }
        for (left, right) in zip(first, second) {
            guard left.count == right.count else { return false }
            let leftBase = left.withUnsafeBufferPointer { $0.baseAddress }
            let rightBase = right.withUnsafeBufferPointer { $0.baseAddress }
            guard unsafe leftBase == rightBase else { return false }
        }
        return true
    }
}

/// A draw-group list and the indices of its groups that cast shadows. The indices
/// point into `groups`, because the GPU cull numbers the groups of the same list.
nonisolated struct ShadowCasterList {
    var groups: [DrawGroup] = []
    var casters: [Int] = []

    static func casterIndices(of groups: [DrawGroup]) -> [Int] {
        var result: [Int] = []
        for index in groups.indices where groups[index].castsShadows {
            result.append(index)
        }
        return result
    }
}
