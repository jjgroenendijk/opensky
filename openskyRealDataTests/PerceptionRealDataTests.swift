// Real-install perception evidence (issue #202, roadmap item 16.6): the
// detection GMSTs as the shipped game carries them, and a real Whiterun guard
// picking up a player who walks toward it across the real city geometry.
//
// No game bytes or frames leave the read-only install; the guard's identity,
// the state transitions and the timings are printed into the realtest run.

import Foundation
import Metal
@testable import opensky
import simd
import Testing

@MainActor
struct PerceptionRealDataTests {
    /// How far out the approach starts and how far each stride carries it,
    /// world units. Twenty-eight strides from 2800 units closes to inside a
    /// guard's own reach.
    private static let approachStart: Float = 2800
    private static let approachStride: Float = 100
    /// Fixed steps spent standing at each stride, which is what turns an
    /// approach into a sequence of states rather than one jump.
    private static let stepsPerStride = 20

    nonisolated private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    nonisolated private static let device: MTLDevice? = {
        guard let device = MTLCreateSystemDefaultDevice(), device.supportsFamily(.metal4)
        else { return nil }
        return device
    }()

    // MARK: - Provenance

    @Test(.enabled(if: Self.dataRoot != nil))
    func everyVanillaDetectionSettingResolvesFromTheLoadOrder() throws {
        let root = try #require(Self.dataRoot)
        let settings = DetectionSettings.resolve(
            store: GameSettingLoader.load(root: root)
        )
        // The ten load-order settings must come from a plugin, not from the
        // fallback: a fallback here would mean the formula is running on
        // numbers this install does not actually carry.
        let vanilla = settings.report.prefix(10)
        for row in vanilla {
            let source = row.setting.source.lowercased()
            #expect(
                source.hasSuffix(".esm") || source.hasSuffix(".esp"),
                Comment(rawValue: "\(row.editorID) fell back to \(row.setting.source)")
            )
        }
        // And the values are the ones the formula was written against.
        #expect(settings.sneakBaseValue.value == -15)
        #expect(settings.maxDistance.value == 2500)
        #expect(settings.exteriorDistanceMult.value == 2.1)
        #expect(settings.soundLosMult.value == 0.3)
        // Everything after those ten is ours and says so, which is the honesty
        // rule the docs page states.
        let ours = settings.report.dropFirst(10)
        #expect(ours.allSatisfy { $0.setting.source == "OpenSky constant" })
        for row in settings.report {
            print("[INFO] detection \(row.editorID) = \(row.setting.value) "
                + "[\(row.setting.source)]")
        }
    }

    // MARK: - The guard

    @Test(.enabled(if: Self.dataRoot != nil && Self.device != nil))
    func aWhiterunGuardDetectsTheApproachingPlayer() throws {
        let root = try #require(Self.dataRoot)
        let scene = try WhiterunGuardFixture.buildCell(
            root: root, device: #require(Self.device)
        )
        let file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))
        let located = try #require(
            WhiterunGuardFixture.locate(
                in: scene, templates: WhiterunGuardFixture.templates(root: root)
            ),
            Comment(rawValue: "no \(WhiterunGuardFixture.editorIDPrefix) ACHR in "
                + "\(WhiterunGuardFixture.worldspace) "
                + "(\(WhiterunGuardFixture.cell.x),\(WhiterunGuardFixture.cell.y))")
        )
        #expect(!scene.staticCollision.shapes.isEmpty)

        let observer = PerceptionObserver(
            key: located.key,
            feet: located.actor.placement.position,
            facing: located.actor.placement.rotation.z,
            isExterior: true,
            name: located.editorID
        )
        let world = FakePerceptionWorld(observers: [observer])
        world.blocked = WhiterunGuardFixture.blockedPredicate(against: scene.staticCollision)
        let runtime = PerceptionRuntime(
            settings: DetectionSettings.resolve(
                store: GameSettingLoader.load(root: root, baseFile: file)
            ),
            world: world
        )

        let startedAt = DispatchTime.now().uptimeNanoseconds
        let walk = Self.approach(runtime: runtime, world: world, observer: observer)
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000

        // The states arrive in order and end in detection. Only the order is
        // pinned, not the exact stride each transition falls on: that depends
        // on where the guard is standing, and this test is evidence that the
        // pass works on real geometry rather than a second copy of the
        // synthetic thresholds.
        #expect(walk.states == [.unaware, .suspicious, .detected])
        let final = runtime.state(observer: located.key, target: .player)
        #expect(final.lastKnownPosition != nil)
        #expect(final.hasLineOfSight)
        let order = walk.states.map(\.rawValue).joined(separator: " -> ")
        let position = "(\(observer.feet.x), \(observer.feet.y), \(observer.feet.z))"
        print("[INFO] \(located.editorID) (\(located.key)) at \(position)")
        print("[INFO] states \(order) over \(Self.approachStart) units, "
            + "\(runtime.lineOfSightQueryCount) rays, \(elapsed) ms offscreen")
        print("[INFO] DetectionStatsLabel: \(walk.lastLine)")
    }

    // MARK: - The approach

    /// Walks the target in along the guard's facing, returning the distinct
    /// states it passed through and the last readout line.
    private static func approach(
        runtime: PerceptionRuntime,
        world: FakePerceptionWorld,
        observer: PerceptionObserver
    ) -> (states: [DetectionState], lastLine: String) {
        let heading = SIMD3<Float>(observer.heading.x, observer.heading.y, 0)
        var states: [DetectionState] = []
        var lastLine = ""
        var distance = approachStart
        while distance > 0 {
            world.targets = [PerceptionTarget(
                key: .player,
                feet: observer.feet + heading * distance,
                gait: .walk,
                name: "Player"
            )]
            for _ in 0 ..< stepsPerStride {
                runtime.advance(by: PerceptionRuntime.fixedStepSeconds)
            }
            let pair = runtime.state(observer: observer.key, target: .player)
            if states.last != pair.state {
                states.append(pair.state)
            }
            lastLine = runtime.readout().pairs.first?.summaryLine ?? lastLine
            distance -= approachStride
        }
        return (states, lastLine)
    }
}
