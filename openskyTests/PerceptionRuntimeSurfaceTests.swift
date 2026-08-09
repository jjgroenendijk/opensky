// The perception pass's bounds, readout, condition seam and overlay (issue
// #202, roadmap item 16.6), split from `PerceptionRuntimeTests` when that type
// reached the strict-lint body cap.
//
// The split is along a real seam: the other half is about what an observer
// perceives, and this half is about what the pass costs and what it hands out.

@testable import opensky
import simd
import Testing

@MainActor
extension PerceptionRuntimeTests {
    @Test func thePairCapDropsTheFurthestPairsAndSaysHowMany() {
        let observers = (1 ... PerceptionRuntime.maximumPairs + 4).map { index in
            PerceptionFixture.observer(
                key: ReferenceKey.plugin(name: "perception.esm", objectID: UInt32(index)),
                feet: SIMD3(Float(index) * 10, 0, 0),
                name: "Guard \(index)"
            )
        }
        let world = FakePerceptionWorld(
            observers: observers,
            targets: [PerceptionFixture.target(feet: SIMD3(0, 0, 0))]
        )
        let runtime = PerceptionRuntime(settings: settings, world: world)
        advance(runtime, steps: 200)
        #expect(runtime.droppedPairCount == 4)
        #expect(runtime.readout().droppedPairCount == 4)
        #expect(runtime.pairs.count <= PerceptionRuntime.maximumPairs)
        // The nearest observers are the ones kept.
        let kept = Set(runtime.pairs.keys.map(\.observer))
        #expect(kept.contains(observers[0].key))
        #expect(!kept.contains(observers[observers.count - 1].key))
    }

    @Test func slicingCostsOneRayPerEvaluatedPairAndNotOnePerPairPerStep() {
        let observers = (1 ... 16).map { index in
            PerceptionFixture.observer(
                key: ReferenceKey.plugin(name: "perception.esm", objectID: UInt32(index)),
                feet: SIMD3(0, Float(index) * 10, 0),
                name: "Guard \(index)"
            )
        }
        let world = FakePerceptionWorld(
            observers: observers,
            targets: [PerceptionFixture.target(feet: SIMD3(200, 0, 0))]
        )
        let runtime = PerceptionRuntime(settings: settings, world: world)
        advance(runtime, steps: 4)
        // Four steps at eight pairs a step, not four steps times sixteen pairs.
        #expect(runtime.lineOfSightQueryCount == 4 * PerceptionRuntime.pairsPerStep)
        #expect(world.lineOfSightQueries.count == runtime.lineOfSightQueryCount)
    }

    @Test func aPairPastEveryRangeCostsNoRayAtAll() {
        let world = FakePerceptionWorld(
            observers: [PerceptionFixture.observer(feet: SIMD3(0, 0, 0))],
            targets: [PerceptionFixture.target(feet: SIMD3(50000, 0, 0))]
        )
        let runtime = PerceptionRuntime(settings: settings, world: world)
        advance(runtime, steps: 10)
        #expect(runtime.lineOfSightQueryCount == 0)
        #expect(runtime.state(observer: PerceptionFixture.guardKey, target: .player)
            .state == .unaware)
    }

    @Test func aPausedFrameAdvancesNothing() {
        let world = FakePerceptionWorld(
            observers: [PerceptionFixture.observer(feet: SIMD3(0, 0, 0))],
            targets: [PerceptionFixture.target(feet: SIMD3(200, 0, 0))]
        )
        let runtime = PerceptionRuntime(settings: settings, world: world)
        #expect(runtime.advance(by: 0) == 0)
        #expect(runtime.advance(by: -1) == 0)
        #expect(runtime.advance(by: .nan) == 0)
        #expect(runtime.stepCount == 0)
        // A long stall runs the capped number of steps and no more.
        #expect(runtime.advance(by: 10) == PerceptionRuntime.maximumStepsPerAdvance)
    }

    // MARK: - Readout, condition seam and overlay

    @Test func theReadoutNamesThePairAndCarriesTheStatsLabelLine() {
        let world = FakePerceptionWorld(
            observers: [PerceptionFixture.observer(feet: SIMD3(0, 0, 0))],
            targets: [PerceptionFixture.target(feet: SIMD3(400, 0, 0))]
        )
        let runtime = PerceptionRuntime(settings: settings, world: world)
        advance(runtime, steps: 120)
        let readout = runtime.readout()
        #expect(readout.observerCount == 1)
        #expect(readout.targetCount == 1)
        #expect(readout.pairs.count == 1)
        let row = readout.pairs[0]
        #expect(row.observerName == "Guard")
        #expect(row.targetName == "Player")
        #expect(row.state == .detected)
        #expect(row.summaryLine.contains("Guard -> Player"))
        #expect(row.summaryLine.contains("detected"))
        #expect(row.summaryLine.contains("last seen (400, 0, 0)"))
        #expect(readout.pairs(involving: .player).count == 1)
        #expect(readout.pairs(involving: PerceptionFixture.secondGuardKey).isEmpty)
    }

    @Test func theConditionSeamCarriesEveryPairAndEveryPosition() {
        let world = FakePerceptionWorld(
            observers: [PerceptionFixture.observer(feet: SIMD3(0, 0, 0))],
            targets: [PerceptionFixture.target(feet: SIMD3(300, 400, 0))]
        )
        let runtime = PerceptionRuntime(settings: settings, world: world)
        advance(runtime, steps: 120)
        let resolution = runtime.resolution()
        #expect(!resolution.isEmpty)
        #expect(resolution.pairCount == 1)
        #expect(resolution.pair(observer: PerceptionFixture.guardKey, target: .player)?
            .isDetected == true)
        // Nothing observes the player's own view, so the reversed pair is a
        // gap rather than an "undetected".
        #expect(resolution.pair(observer: .player, target: PerceptionFixture.guardKey) == nil)
        #expect(resolution.distance(from: PerceptionFixture.guardKey, to: .player) == 500)
        #expect(resolution.distance(from: .player, to: PerceptionFixture.secondGuardKey) == nil)
        #expect(DetectionResolution.empty.isEmpty)
    }

    @Test func theOverlayDrawsAConeAndAMemoryLineOnlyWhenEnabled() {
        let world = FakePerceptionWorld(
            observers: [PerceptionFixture.observer(feet: SIMD3(0, 0, 0))],
            targets: [PerceptionFixture.target(feet: SIMD3(400, 0, 0))]
        )
        let runtime = PerceptionRuntime(settings: settings, world: world)
        advance(runtime, steps: 120)

        var off = WorldOverlayDrawList()
        runtime.appendWorldOverlay(context: WorldOverlayFrameContext(), to: &off)
        #expect(off.primitiveCount == 0)

        var on = WorldOverlayDrawList()
        runtime.appendWorldOverlay(
            context: WorldOverlayFrameContext(detectionOverlayEnabled: true), to: &on
        )
        // One fan plus the line back to the investigate position.
        #expect(on.primitiveCount == PerceptionOverlay.coneSegmentCount + 1)
        let budgeted = on.budgeted(maxPrimitives: 4096)
        #expect(budgeted.triangleCount == PerceptionOverlay.coneSegmentCount)
        #expect(budgeted.lineSegmentCount == 1)
        // A detected observer is drawn in the detected colour.
        #expect(budgeted.vertices[0].color == PerceptionOverlay.detectedColor)
        #expect(PerceptionOverlay.color(for: .unaware) == PerceptionOverlay.unawareColor)
        #expect(PerceptionOverlay.color(for: .suspicious) == PerceptionOverlay.suspiciousColor)
    }

    @Test func detachingTheWorldForgetsEveryPair() {
        let world = FakePerceptionWorld(
            observers: [PerceptionFixture.observer(feet: SIMD3(0, 0, 0))],
            targets: [PerceptionFixture.target(feet: SIMD3(200, 0, 0))]
        )
        let runtime = PerceptionRuntime(settings: settings, world: world)
        advance(runtime, steps: 60)
        #expect(!runtime.pairs.isEmpty)
        runtime.attach(world: nil)
        #expect(runtime.pairs.isEmpty)
        #expect(runtime.stepCount == 0)
        #expect(runtime.readout() == .empty)
        #expect(runtime.advance(by: 1) == 0)
    }
}
