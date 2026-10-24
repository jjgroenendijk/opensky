// The perk sky's pure parts: where stars and lines go and which state each shows,
// how the camera turns and moves in, and which sequence each star plays.

import Foundation
@testable import OpenSkyMenus
import OpenSkyProgressionInterface
import simd
import Testing

@MainActor
struct PerkSkyTests {
    private static func perk(
        _ node: UInt32, x: Float, y: Float, to connections: [UInt32] = [], owned: Bool = false
    ) -> SkillsMenuPerk {
        SkillsMenuPerk(
            node: node, name: "Perk \(node)", description: "", requirement: "", gridX: x,
            gridY: y, connections: connections, ownedRank: owned ? 1 : 0, rankCount: 1,
            refusal: nil
        )
    }

    private static func close(_ lhs: SIMD3<Float>, _ rhs: SIMD3<Float>) -> Bool {
        simd_distance(lhs, rhs) < 0.001
    }

    @Test func slotsTurnClockwiseFromPointZero() {
        #expect(Self.close(PerkSkyLayout.defaultAnchor(slot: 0), [0, 99.34, 0]))
        let right = PerkSkyLayout.defaultAnchor(slot: 1)
        #expect(right.x > 33 && right.x < 35, "slot 1 is 20 degrees to the right")
        #expect(PerkSkyLayout.anchorName(slot: 7) == "Point07")
    }

    @Test func starsMirrorAcrossAndLeanBackFromTheAnchor() {
        let settings = PerkSkySettings()
        let stars = PerkSkyLayout.stars(
            [
                Self.perk(1, x: 2, y: 0, to: [2], owned: true),
                Self.perk(2, x: 3, y: 1, to: [3]),
                Self.perk(3, x: 1, y: 2)
            ],
            slot: 0, anchor: [0, 100, 0], selected: nil, settings: settings
        )
        let row = settings.rowScale
        #expect(Self.close(stars[0].position, [0, 95, 0]), "column 2 is the centre of 1 to 3")
        #expect(
            Self.close(stars[1].position, [-5, 95 + 9 * row, 15 * row]),
            "a higher column sits to the left, and a higher row further out"
        )
        #expect(stars.map(\.state) == [.owned, .unlocked, .locked])
    }

    @Test func aBoxWithoutAParentIsReachableAndTheSelectionWins() {
        let stars = PerkSkyLayout.stars(
            [Self.perk(4, x: 2, y: 0), Self.perk(5, x: 2, y: 1, owned: true)],
            slot: 3, anchor: .zero, selected: 5, settings: PerkSkySettings()
        )
        #expect(stars.map(\.state) == [.unlocked, .selected])
    }

    @Test func aLineLightsOnceItsLowerPerkIsOwned() {
        let perks = [
            Self.perk(1, x: 2, y: 0, to: [2], owned: true), Self.perk(2, x: 2, y: 1, to: [3]),
            Self.perk(3, x: 2, y: 2)
        ]
        let stars = PerkSkyLayout.stars(
            perks, slot: 0, anchor: .zero, selected: nil, settings: PerkSkySettings()
        )
        let lines = PerkSkyLayout.lines(perks, stars: stars)
        #expect(lines.map(\.state) == [.unlocked, .locked])
        #expect(lines.first.map { Self.close($0.to, stars[1].position) } == true)
    }

    @Test func settingsReadTheLoadOrderAndKeepTheRest() {
        let values: [String: Float] = [
            "fStatsCameraFOV": 60, "fStatsStarLookAtX": 1, "fStatsStarLookAtY": 2,
            "fStatsStarLookAtZ": 3, "fStatsSkillsLookAtX": 9
        ]
        let settings = PerkSkySettings { values[$0] }
        #expect(settings.cameraFOV == 60)
        #expect(settings.starLookAt == [1, 2, 3])
        #expect(
            settings.skillsLookAt == PerkSkySettings().skillsLookAt,
            "one axis alone is ignored"
        )
    }

    @Test func theCameraTurnsTheShortWayAndRampsUp() {
        var settings = PerkSkySettings()
        settings.rotationSpeedMax = 100
        settings.rotationRampTime = 1
        var motion = PerkSkyMotion(slot: 0)
        motion.update(now: 0, slot: 17, slotCount: 18, inTree: false, settings: settings)
        motion.update(now: 0.1, slot: 17, slotCount: 18, inTree: false, settings: settings)
        #expect(motion.yawDegrees < 0, "slot 17 is one step left of slot 0")
        #expect(motion.yawDegrees > -2, "the turn starts slow")
        for tick in 2 ... 40 {
            motion.update(
                now: Double(tick) * 0.1, slot: 17, slotCount: 18, inTree: true, settings: settings
            )
        }
        #expect(motion.yawDegrees == 340)
        #expect(motion.treeBlend == 1)
    }

    @Test func theTreeCameraBlendsFromTheRingCamera() {
        let settings = PerkSkySettings()
        let ring = PerkSkyLayout.camera(
            yawDegrees: 0, treeBlend: 0, introOffset: [0, 0, -50], settings: settings
        )
        #expect(ring.eye == [0, 0, -50])
        #expect(Self.close(ring.target, settings.skillsLookAt + [0, 0, -50]))
        let tree = PerkSkyLayout.camera(
            yawDegrees: 90, treeBlend: 1, introOffset: .zero, settings: settings
        )
        let offset = settings.starCameraOffset
        #expect(Self.close(tree.eye, [offset.y, -offset.x, offset.z]))
    }

    @Test func aStarPlaysItsTransitionThenSettles() {
        var animator = PerkSkyAnimator<Int>()
        let duration: (String) -> Float? = { $0 == "Own" ? Float(0.5) : Float(3) }
        let transition: (String) -> String? = {
            PerkStarState(rawValue: $0)?.transition(to: .owned)
        }
        let first = animator.playback(
            1, state: "Unlocked", transition: { _ in nil }, now: 0, duration: duration
        )
        #expect(first.sequence == "Unlocked")
        let buy = animator.playback(
            1, state: "Owned", transition: transition, now: 1, duration: duration
        )
        #expect(buy.sequence == "Own")
        #expect(buy.next == "Owned")
        let held = animator.playback(
            1, state: "Owned", transition: transition, now: 1.2, duration: duration
        )
        #expect(held.sequence == "Own")
        let settled = animator.playback(
            1, state: "Owned", transition: transition, now: 1.6, duration: duration
        )
        #expect(settled.sequence == "Owned")
        #expect(PerkStarState.selected.transition(to: .owned) == "Deselect")
        #expect(PerkLineState.locked.transition(to: .unlocked) == "Unlock")
    }

    @Test func aLineStretchesFromItsLowerStarToItsUpperStar() {
        let basis = SkillsMenuCoordinator.lineBasis(
            from: [1, 2, 3], to: [1, 2, 13], meshLength: 5, width: 0.5
        )
        let end = basis * SIMD4<Float>(0, 5, 0, 1)
        #expect(Self.close(SIMD3(end.x, end.y, end.z), [1, 2, 13]))
        #expect(abs(simd_length(SIMD3(basis.columns.0.x, basis.columns.0.y, basis.columns.0.z))
                - 0.5) < 0.001)
    }
}
