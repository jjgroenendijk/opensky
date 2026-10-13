// Where the perk sky puts each star and line, and where its camera stands. All
// positions are in the space of `intperkskydome.nif`: the ring of `Point00` to
// `Point17` lies flat around the origin, and +Z is up. See docs/engine/perk-sky.md.

import Foundation
import OpenSkyProgressionInterface
import simd

nonisolated public struct PerkSkyStar: Equatable, Sendable {
    public let node: UInt32
    public let position: SIMD3<Float>
    public let state: PerkStarState
}

nonisolated public struct PerkSkyLine: Equatable, Sendable {
    public let parent: UInt32
    public let child: UInt32
    public let from: SIMD3<Float>
    public let to: SIMD3<Float>
    public let state: PerkLineState
}

nonisolated public struct PerkSkyCamera: Equatable, Sendable {
    public var eye: SIMD3<Float>
    public var target: SIMD3<Float>
    public var up: SIMD3<Float> = [0, 0, 1]
}

nonisolated public enum PerkSkyLayout {
    /// Degrees between two ring slots, as the movie's `SKILL_ANGLE`.
    public static let slotDegrees: Float = 20
    /// The dome's ring radius, used when the mesh lacks a `Point` node.
    static let ringRadius: Float = 99.34

    public static func anchorName(slot: Int) -> String {
        String(format: "Point%02d", slot)
    }

    /// Turns a vector from the frame of the skill ahead into dome space. Slots go
    /// clockwise seen from above, so slot 1 is to the right of slot 0.
    public static func rotate(_ vector: SIMD3<Float>, yawDegrees: Float) -> SIMD3<Float> {
        simd_quatf(angle: -yawDegrees * .pi / 180, axis: [0, 0, 1]).act(vector)
    }

    public static func defaultAnchor(slot: Int) -> SIMD3<Float> {
        rotate([0, ringRadius, 0], yawDegrees: Float(slot) * slotDegrees)
    }

    /// The stars of one tree, grown up from its anchor. `selected` is the box the
    /// tree page has on; nil on the ring.
    public static func stars(
        _ perks: [SkillsMenuPerk], slot: Int, anchor: SIMD3<Float>, selected: UInt32?,
        settings: PerkSkySettings
    ) -> [PerkSkyStar] {
        let parents = parentMap(perks)
        let owned = Set(perks.filter(\.isOwned).map(\.node))
        return perks.map { perk in
            let state: PerkStarState = if perk.node == selected {
                .selected
            } else if perk.isOwned {
                .owned
            } else if isReachable(perk.node, parents: parents, owned: owned) {
                .unlocked
            } else {
                .locked
            }
            return PerkSkyStar(
                node: perk.node,
                position: position(perk, slot: slot, anchor: anchor, settings: settings),
                state: state
            )
        }
    }

    /// One line per connection inside the tree, lit once its upper end can be bought.
    public static func lines(_ perks: [SkillsMenuPerk], stars: [PerkSkyStar]) -> [PerkSkyLine] {
        let positions = Dictionary(
            stars.map { ($0.node, $0.position) }, uniquingKeysWith: { first, _ in first }
        )
        let owned = Set(perks.filter(\.isOwned).map(\.node))
        return perks.flatMap { perk in
            perk.connections.compactMap { child -> PerkSkyLine? in
                guard let from = positions[perk.node], let to = positions[child] else {
                    return nil
                }
                return PerkSkyLine(
                    parent: perk.node, child: child, from: from, to: to,
                    state: owned.contains(perk.node) ? .unlocked : .locked
                )
            }
        }
    }

    /// `fStatsStar*Increment` steps across, up, and inward per row, from the anchor.
    static func position(
        _ perk: SkillsMenuPerk, slot: Int, anchor: SIMD3<Float>, settings: PerkSkySettings
    ) -> SIMD3<Float> {
        let step = settings.starIncrement
        let local = SIMD3<Float>(
            (perk.gridX - 2) * step.x,
            settings.starZInitialOffset + perk.gridY * step.z * settings.rowScale,
            perk.gridY * step.y * settings.rowScale
        )
        return anchor + rotate(local, yawDegrees: Float(slot) * slotDegrees)
    }

    /// A box with no parent in the tree hangs off the entry node, so it is always reachable.
    static func isReachable(
        _ node: UInt32, parents: [UInt32: [UInt32]], owned: Set<UInt32>
    ) -> Bool {
        guard let above = parents[node], !above.isEmpty else { return true }
        return above.contains(where: owned.contains)
    }

    static func parentMap(_ perks: [SkillsMenuPerk]) -> [UInt32: [UInt32]] {
        let nodes = Set(perks.map(\.node))
        var parents: [UInt32: [UInt32]] = [:]
        for perk in perks {
            for child in perk.connections where nodes.contains(child) {
                parents[child, default: []].append(perk.node)
            }
        }
        return parents
    }

    /// The ring camera at `yaw`, moved toward the tree camera by `treeBlend` (0 to 1),
    /// then lifted by `introOffset` while the opening move plays.
    public static func camera(
        yawDegrees: Float, treeBlend: Float, introOffset: SIMD3<Float>,
        settings: PerkSkySettings
    ) -> PerkSkyCamera {
        let blend = treeBlend * treeBlend * (3 - 2 * treeBlend)
        let eye = simd_mix(SIMD3<Float>.zero, settings.starCameraOffset, SIMD3(repeating: blend))
        let target = simd_mix(settings.skillsLookAt, settings.starLookAt, SIMD3(repeating: blend))
        return PerkSkyCamera(
            eye: rotate(eye, yawDegrees: yawDegrees) + introOffset,
            target: rotate(target, yawDegrees: yawDegrees) + introOffset
        )
    }
}
